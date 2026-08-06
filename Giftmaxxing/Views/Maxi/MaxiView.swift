import SwiftUI

// Shared, not per-sheet: the conversation is the product. A concierge that
// restarts the interview every time you close the sheet is a search box with
// extra steps.
@MainActor
final class MaxiViewModel: ObservableObject {
    static let shared = MaxiViewModel()

    @Published var messages: [MaxiMessage] = []
    @Published var inputText = ""
    @Published var isThinking = false
    /// Set when an action lands, so the chat can confirm it inline.
    @Published var lastCartConfirmation: String?
    /// What Maxi currently thinks the job is — shown as a chip so the user can
    /// see the assumptions behind the picks.
    @Published var brief: GiftBrief?

    private let api = APIClient.shared
    private var catalog: [Post] = []

    private static let greeting = MaxiMessage(
        role: .assistant,
        // One question, not a manifesto — the workflow starts by naming the
        // person, and everything else follows from that.
        text: "Who are we shopping for?",
        products: [],
        steps: [],
        chips: MaxiLocalEngine.seedChips
    )

    private init() {
        let saved = MaxiConversationStore.shared.messages
        messages = saved.isEmpty ? [Self.greeting] : saved
    }

    func send(_ text: String) {
        inputText = text
        Task { await sendMessage() }
    }

    /// Open the chat already focused on someone (from a cart section or a Gift
    /// Board) so it starts mid-job instead of at "who is this for?".
    func seed(recipient: String) {
        guard !recipient.isEmpty,
              recipient != CartSection.unassignedName else { return }
        send("Help me pick something for \(recipient).")
    }

    /// New conversation, same account.
    func startOver() {
        MaxiConversationStore.shared.reset()
        messages = [Self.greeting]
    }

    /// Account switch / sign-out wiped the transcript — drop it from memory too.
    func resetToGreeting() {
        messages = [Self.greeting]
        catalog = []
    }

    private func record(_ message: MaxiMessage) {
        messages.append(message)
        MaxiConversationStore.shared.append(message)
    }

    // Product catalog for the local fallback engine (web runs respond() over
    // its bundled pins; we use the live feed and cache it for the session).
    private func loadCatalogIfNeeded() async {
        guard catalog.isEmpty else { return }
        if let page = try? await api.fetchFeed(limit: 60) {
            catalog = page.posts
        }
    }

    func sendMessage() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        record(MaxiMessage(role: .user, text: text))
        inputText = ""
        isThinking = true

        let history = MaxiConversationStore.shared.history()

        do {
            // Send the signed-in identity: the agent unlocks memory, events and
            // connection tools server-side only when it knows who's asking.
            let reply = try await api.askMaxi(
                userId: AuthManager.shared.userId,
                name: AuthManager.shared.displayName,
                message: text,
                history: history
            )
            if let reply, !reply.say.isEmpty {
                record(MaxiMessage(
                    role: .assistant,
                    text: reply.say,
                    products: reply.pins,
                    steps: reply.steps
                ))
                if let replyBrief = reply.brief, !replyBrief.isEmpty {
                    brief = replyBrief
                }
                // The agent doesn't write the cart itself — it asks us to, so
                // the local-first store stays the single source of truth.
                for action in reply.actions {
                    apply(action, pins: reply.pins)
                }
            } else {
                await respondLocally(to: text, note: nil)
            }
        } catch APIError.httpError(let code) where code == 401 || code == 403 {
            // Auth-gated agent: be honest about why answers are canned.
            await respondLocally(
                to: text,
                note: "I'm in quick-answers mode — sign in to unlock the full AI concierge (memory, your events, agentic shopping)."
            )
        } catch APIError.httpError(let code) where code == 429 || code == 503 {
            await respondLocally(
                to: text,
                note: "The AI concierge is taking a breather (usage limits). Here's what I can find in the catalog meanwhile."
            )
        } catch {
            await respondLocally(
                to: text,
                note: "You're offline, so I'm answering from the on-device catalog."
            )
        }

        isThinking = false
    }

    // Local fallback (web respond() parity) with a one-time status note so
    // canned answers are never mistaken for the real agent.
    private var shownFallbackNote = false

    private func respondLocally(to text: String, note: String?) async {
        await loadCatalogIfNeeded()
        let local = MaxiLocalEngine.respond(to: text, catalog: catalog)
        var say = local.say
        if let note, !shownFallbackNote {
            shownFallbackNote = true
            say = "\(note)\n\n\(say)"
        }
        record(MaxiMessage(
            role: .assistant,
            text: say,
            products: local.products,
            chips: local.chips
        ))
    }

    // MARK: - Agent actions

    private func apply(_ action: MaxiAgentReply.MaxiAction, pins: [MaxiProduct]) {
        switch action.type {
        case "add_to_cart":
            let ids = Set(action.postIds ?? [])
            let chosen = pins.filter { ids.contains($0.postId) }
            guard !chosen.isEmpty else { return }
            let recipient = action.recipient?.trimmingCharacters(in: .whitespacesAndNewlines)
            for product in chosen {
                CartStore.shared.add(
                    Post(maxiProduct: product),
                    for: recipient,
                    occasion: action.occasion,
                    source: "maxi"
                )
            }
            let who = (recipient?.isEmpty == false) ? recipient! : "your cart"
            lastCartConfirmation = chosen.count == 1
                ? "Added to \(who)"
                : "Added \(chosen.count) to \(who)"

        case "checkout":
            // The server's checkout is simulated; ours is honest — send them to
            // the cart, where the real affiliate links and the packaging plan
            // live.
            lastCartConfirmation = "Your cart's ready"

        default:
            break
        }
    }
}

struct MaxiView: View {
    /// Opens the conversation already focused on someone (from a cart section
    /// or a Gift Board).
    var seedRecipient: String?

    @ObservedObject private var viewModel = MaxiViewModel.shared
    @StateObject private var speech = SpeechRecognizer()
    @Environment(\.dismiss) private var dismiss
    @State private var showCart = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // What Maxi thinks the job is. Visible so wrong assumptions are
                // correctable, rather than quietly shaping every suggestion.
                if let brief = viewModel.brief, !brief.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "target")
                            .font(.caption)
                        Text(brief.summary)
                            .font(.footnote.weight(.medium))
                            .lineLimit(1)
                        Spacer()
                    }
                    .foregroundStyle(Color.coral)
                    .padding(.horizontal, ThemeSpacing.md)
                    .padding(.vertical, 6)
                    .background(Color.coralSoft)
                    .accessibilityLabel("Shopping for \(brief.summary)")
                }

                // Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.messages) { message in
                                MaxiMessageBubble(message: message) { chip in
                                    viewModel.send(chip)
                                }
                                .id(message.id)
                            }

                            if viewModel.isThinking {
                                HStack(spacing: 8) {
                                    MaxiIcon(size: 28)
                                    TypingIndicator()
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .id("thinking")
                            }
                        }
                        .padding(.vertical, 16)
                    }
                    .onChange(of: viewModel.messages.count) { _, _ in
                        withAnimation {
                            proxy.scrollTo(viewModel.messages.last?.id ?? "thinking", anchor: .bottom)
                        }
                    }
                }

                // Inline confirmation when the agent lands something in the
                // cart — the action has to be visible, or "added it" is a claim
                // the user can't check without leaving the conversation.
                if let confirmation = viewModel.lastCartConfirmation {
                    Button {
                        showCart = true
                        viewModel.lastCartConfirmation = nil
                    } label: {
                        HStack(spacing: ThemeSpacing.xs) {
                            Image(systemName: "bag.fill")
                            Text(confirmation)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("View")
                                .font(.subheadline.weight(.bold))
                        }
                        .foregroundStyle(Color.coral)
                        .padding(.horizontal, ThemeSpacing.md)
                        .padding(.vertical, ThemeSpacing.sm)
                        .background(Color.coralSoft)
                    }
                    .buttonStyle(.plain)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                Divider()

                // Voice status / errors
                if speech.isRecording {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(.red)
                            .frame(width: 8, height: 8)
                        Text(speech.transcript.isEmpty ? "Listening\u{2026}" : speech.transcript)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.ink)
                            .lineLimit(2)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.coralSoft)
                } else if let voiceError = speech.errorMessage {
                    Text(voiceError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                }

                // Input
                HStack(spacing: 10) {
                    TextField("Ask Maxi anything...", text: $viewModel.inputText, axis: .vertical)
                        .font(.bodyMedium)
                        .lineLimit(1...4)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.cream)
                        .clipShape(RoundedRectangle(cornerRadius: 20))

                    // Voice input (Amazon-style voice shopping)
                    Button(action: { speech.toggle() }) {
                        Image(systemName: speech.isRecording ? "stop.circle.fill" : "mic.fill")
                            .font(.system(size: speech.isRecording ? 32 : 20, weight: .semibold))
                            .foregroundStyle(speech.isRecording ? .red : Color.coral)
                            .frame(width: 36, height: 36)
                    }

                    Button(action: {
                        Task { await viewModel.sendMessage() }
                    }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(
                                viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? Color.gray.opacity(0.4)
                                    : Color.coral
                            )
                    }
                    .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isThinking)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.surface)
                .onChange(of: speech.isRecording) { wasRecording, isRecording in
                    // Recording just stopped with a transcript \u{2192} send it to Maxi.
                    if wasRecording && !isRecording {
                        let heard = speech.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !heard.isEmpty {
                            viewModel.send(heard)
                            speech.transcript = ""
                        }
                    }
                }
            }
            .background(Color.surface)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.ink)
                    }
                    .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        MaxiIcon(size: 24)
                        Text("Ask Maxi")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                        Text("AI")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.coral)
                            .clipShape(Capsule())
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showCart = true
                        } label: {
                            Label("Open cart", systemImage: "bag")
                        }
                        Button(role: .destructive) {
                            viewModel.startOver()
                        } label: {
                            Label("Start over", systemImage: "arrow.counterclockwise")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.ink)
                    }
                    .accessibilityLabel("Conversation options")
                }
            }
            .navigationDestination(isPresented: $showCart) { CartView() }
        }
        .task {
            // Arriving from a cart section or a Gift Board: start mid-job.
            if let seedRecipient, !seedRecipient.isEmpty {
                viewModel.seed(recipient: seedRecipient)
            }
        }
        .animation(.snappy, value: viewModel.lastCartConfirmation)
    }
}

struct MaxiMessageBubble: View {
    let message: MaxiMessage
    var onChipTap: ((String) -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .assistant {
                MaxiIcon(size: 28)
            } else {
                Spacer(minLength: 60)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                // Text
                Text(message.text)
                    .font(.bodyMedium)
                    .foregroundStyle(message.role == .user ? .white : Color.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        message.role == .user
                            ? AnyShapeStyle(Color.coral)
                            : AnyShapeStyle(Color.cream)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                // Steps
                if !message.steps.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(message.steps) { step in
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.green)
                                Text(step.label)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                }

                // Products
                if !message.products.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(message.products) { product in
                                MaxiProductCard(product: product)
                            }
                        }
                    }
                }

                // Suggestion chips (web parity)
                if !message.chips.isEmpty && message.role == .assistant {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(message.chips, id: \.self) { chip in
                                Button {
                                    onChipTap?(chip)
                                } label: {
                                    Text(chip)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Color.coral)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .background(Color.coralSoft)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                }
            }

            if message.role == .user {
                // no trailing icon for user
            } else {
                Spacer(minLength: 40)
            }
        }
        .padding(.horizontal, 16)
    }
}

struct MaxiProductCard: View {
    let product: MaxiProduct
    @State private var browserTarget: BrowserTarget?

    private var outboundURL: URL? {
        let query = [product.title, product.brand ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return URL(string: Affiliate.searchUrl(query: query.isEmpty ? "gifts" : query))
    }

    var body: some View {
        cardBody
            .onTapGesture {
                if let url = outboundURL {
                    OutboundRouter.open(url, postId: product.postId, source: "maxi") {
                        browserTarget = BrowserTarget(url: $0)
                    }
                }
            }
            .sheet(item: $browserTarget) { target in
                SafariView(url: target.url)
                    .ignoresSafeArea()
            }
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                Color.gradient(for: .coral)
                if let image = product.image, let url = URL(string: image) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        }
                    }
                } else {
                    BrandGlyph(size: 30, tile: false)
                        .font(.system(size: 28))
                }
            }
            .frame(width: 120, height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(product.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.ink)
                .lineLimit(2)
                .frame(width: 120, alignment: .leading)

            if let price = product.price {
                Text("$\(Int(price))")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.coral)
            }
        }
    }
}

struct TypingIndicator: View {
    @State private var phase = 0.0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.ink.opacity(0.4))
                    .frame(width: 7, height: 7)
                    .offset(y: sin(phase + Double(i) * .pi / 3) * 3)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.cream)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .onAppear {
            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
    }
}
