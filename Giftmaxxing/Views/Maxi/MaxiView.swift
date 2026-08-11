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

    /// One-tap verdict on a set of picks. Set-level feedback is weaker than a
    /// deliberate swipe — the user is judging the batch, not each item — so the
    /// taste events carry a reduced weight, but they are still real labels on
    /// items the ranker actually served, which is exactly what it is starved of.
    func rate(_ message: MaxiMessage, rating: Int) {
        guard let i = messages.firstIndex(where: { $0.id == message.id }),
              messages[i].rating == nil else { return }
        messages[i].rating = rating
        MaxiConversationStore.shared.rate(messageId: message.id, rating: rating)

        let liked = rating > 0
        let products = message.products
        Task {
            for product in products {
                let post = Post(maxiProduct: product)
                let signals = TasteSignals.extract(from: post)
                await TasteProfileStore.shared.record(TasteEvent(
                    kind: liked ? .like : .hide,
                    postId: product.postId,
                    author: post.user,
                    price: product.price ?? post.product.price,
                    vibes: signals.vibes,
                    category: signals.category,
                    giftType: post.giftType ?? "product",
                    weightScale: 0.6
                ))
                await InteractionQueue.shared.enqueue(
                    userId: AuthManager.shared.userId ?? InteractionQueue.anonymousUserId,
                    targetId: product.postId,
                    type: liked ? "like" : "hide",
                    data: ["source": "maxi_rating"]
                )
            }
        }
        // Separate from the per-item labels: this one says whether the ANSWER
        // was good, which is what tells us the concierge is missing.
        AnalyticsEngine.shared.trackMaxiRating(rating: rating, postIds: products.map(\.postId))
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
        restoredForUserId = nil
    }

    private var restoredForUserId: String?

    /// Pull the account's transcript from the server the first time this
    /// identity opens the chat on this device. The local copy is the fast path;
    /// this is what makes a reinstall or a new phone not start from nothing.
    func restoreIfNeeded() async {
        guard let userId = AuthManager.shared.userId, !userId.isEmpty else { return }
        guard restoredForUserId != userId else { return }
        restoredForUserId = userId
        // A local transcript is already the freshest copy — don't clobber it.
        guard MaxiConversationStore.shared.isEmpty else { return }

        guard let turns = try? await APIClient.shared.fetchMaxiHistory(userId: userId),
              !turns.isEmpty else { return }

        var restored: [MaxiMessage] = []
        for turn in turns {
            if let user = turn.user, !user.isEmpty {
                restored.append(MaxiMessage(role: .user, text: user))
            }
            if let say = turn.say, !say.isEmpty {
                restored.append(MaxiMessage(role: .assistant, text: say, products: turn.pins ?? []))
            }
        }
        guard !restored.isEmpty else { return }
        messages = restored
        MaxiConversationStore.shared.replaceAll(restored)
    }

    /// Every product still visible in the transcript, newest last, deduped.
    /// This is what "add all to cart" and "the second one" resolve against.
    private var productsOnScreen: [MaxiProduct] {
        var seen = Set<String>()
        return messages
            .flatMap(\.products)
            .filter { seen.insert($0.postId).inserted }
            .suffix(12)
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
                history: history,
                shownProducts: productsOnScreen
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
            // Resolve against everything in the transcript, not just this
            // turn's results: "add all to cart" refers to products shown
            // several turns ago, and matching only fresh pins silently
            // dropped them.
            var byId: [String: MaxiProduct] = [:]
            for product in productsOnScreen + pins { byId[product.postId] = product }
            let chosen = ids.compactMap { byId[$0] }
            guard !chosen.isEmpty else { return }
            // The model routinely omits `recipient` even when the conversation
            // has established one ("My mom" → "added to your cart", landing in
            // an unassigned pile the user then has to file by hand). Fall back
            // to the brief, which is the whole point of tracking it.
            let recipient = (action.recipient?.trimmingCharacters(in: .whitespacesAndNewlines))
                .flatMap { $0.isEmpty ? nil : $0 }
                ?? brief?.recipientName
            for product in chosen {
                CartStore.shared.add(
                    Post(maxiProduct: product),
                    for: recipient,
                    relationship: brief?.relationship,
                    occasion: action.occasion ?? brief?.occasion,
                    source: "maxi"
                )
            }
            let who = (recipient?.isEmpty == false) ? "\(recipient!)'s cart" : "your cart"
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
    @State private var cartPickerProduct: MaxiProduct?
    @FocusState private var composerFocused: Bool

    // What the single action button means right now. Recording wins over
    // everything (you must be able to stop), then typed text, then voice.
    private var composerMode: ComposerActionButton.Mode {
        if speech.isRecording { return .stopRecording }
        let typed = viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.isEmpty ? .voice : .send
    }

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
                                MaxiMessageBubble(
                                    message: message,
                                    onChipTap: { viewModel.send($0) },
                                    onAddToCart: { cartPickerProduct = $0 },
                                    onRate: { viewModel.rate(message, rating: $0) }
                                )
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
                    // Tapping the transcript puts the keyboard away without
                    // losing the draft — the Alexa/iMessage behaviour. Scroll
                    // dismissal alone is not enough: reading a reply while a
                    // keyboard eats half the screen is the common case.
                    .scrollDismissesKeyboard(.interactively)
                    .onTapGesture { composerFocused = false }
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
                        .focused($composerFocused)
                        .font(.bodyMedium)
                        .lineLimit(1...4)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.cream)
                        .clipShape(RoundedRectangle(cornerRadius: 20))

                    // ONE contextual action button, not two. An empty composer
                    // affords voice; the moment there is something to send, the
                    // same control becomes send. Two permanently-visible buttons
                    // made the user choose between actions only one of which was
                    // ever valid, and left a dead grey arrow sitting there the
                    // whole time you were not typing.
                    ComposerActionButton(
                        mode: composerMode,
                        onVoice: { speech.toggle() },
                        onSend: { Task { await viewModel.sendMessage() } }
                    )
                    .disabled(composerMode == .send && viewModel.isThinking)
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
            // Adding from a card asks who it's for, pre-filled with whoever the
            // brief says we're shopping for — so the common case is one tap.
            .sheet(item: $cartPickerProduct) { product in
                RecipientPickerSheet(
                    posts: [Post(maxiProduct: product)],
                    source: "maxi",
                    occasion: viewModel.brief?.occasion,
                    presetRecipient: viewModel.brief?.recipientName
                )
            }
        }
        .task {
            await viewModel.restoreIfNeeded()
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
    var onAddToCart: ((MaxiProduct) -> Void)?
    var onRate: ((Int) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            bubble

            // The product carousel lives OUTSIDE the bubble column. Inside it
            // the row was squeezed between the avatar and a 40pt trailing
            // spacer, which clipped the third card mid-image; full width lets
            // the cards read as a proper shelf and scroll to the end.
            if !message.products.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(message.products) { product in
                            MaxiProductCard(product: product) {
                                onAddToCart?(product)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 2)
                }
                .scrollClipDisabled()

                // One tap, no question asked. "Were these relevant?" as a
                // sentence is a chore nobody answers; two icons get answered,
                // and the answer is a training label.
                HStack(spacing: ThemeSpacing.sm) {
                    if let rating = message.rating {
                        Label(rating > 0 ? "Thanks — more like these." : "Got it — I'll steer away.",
                              systemImage: rating > 0 ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
                            .font(.caption)
                            .foregroundStyle(Color.inkTertiary)
                    } else {
                        Text("Any good?")
                            .font(.caption)
                            .foregroundStyle(Color.inkTertiary)
                        Button { onRate?(1) } label: {
                            Image(systemName: "hand.thumbsup")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color.inkSecondary)
                                .frame(width: 40, height: 32)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("These were relevant")
                        Button { onRate?(-1) } label: {
                            Image(systemName: "hand.thumbsdown")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color.inkSecondary)
                                .frame(width: 40, height: 32)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("These missed")
                    }
                    Spacer()
                }
                .buttonStyle(.plain)
                .padding(.leading, 52)
                .animation(.snappy, value: message.rating)
            }
        }
    }

    private var bubble: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .assistant {
                MaxiIcon(size: 28)
            } else {
                Spacer(minLength: 60)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                // Text. Assistant replies carry light markdown, so they go
                // through MaxiRichText; the user's own text is literal.
                Group {
                    if message.role == .user {
                        Text(message.text).font(.bodyMedium)
                    } else {
                        MaxiRichText(text: message.text)
                    }
                }
                .foregroundStyle(message.role == .user ? Color.onPrimary : Color.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    message.role == .user
                        ? AnyShapeStyle(Color.coral)
                        : AnyShapeStyle(Color.cream)
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

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

                // Products render full-width below the bubble — see `body`.

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

// A pick Maxi surfaced, as a real card rather than a thumbnail.
//
// The old version was a bare 120pt image with text under it and no action —
// you could tap through to a retailer, but not do the one thing the
// conversation was building toward. Now the card carries the two moves that
// matter: add it to someone's cart, or go look at it.
struct MaxiProductCard: View {
    let product: MaxiProduct
    var onAddToCart: (() -> Void)?

    @State private var browserTarget: BrowserTarget?

    private let width: CGFloat = 152

    private var outboundURL: URL? {
        let query = [product.title, product.brand ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return URL(string: Affiliate.searchUrl(query: query.isEmpty ? "gifts" : query))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cover
            details
        }
        .frame(width: width)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.lg, style: .continuous))
        .shadow(
            color: ThemeElevation.card.color,
            radius: ThemeElevation.card.radius,
            y: ThemeElevation.card.y
        )
        .sheet(item: $browserTarget) { target in
            SafariView(url: target.url).ignoresSafeArea()
        }
    }

    private var cover: some View {
        ZStack {
            Color.surfaceSunken
            if let image = product.image {
                CachedAsyncImage(url: image, width: 400)
            } else {
                Image(systemName: "gift")
                    .font(.title)
                    .foregroundStyle(Color.inkTertiary)
            }
        }
        .frame(width: width, height: width)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture { openProduct() }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("View \(product.title)")
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(product.title)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            if let brand = product.brand, !brand.isEmpty {
                Text(brand)
                    .font(.caption)
                    .foregroundStyle(Color.inkTertiary)
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                if let price = product.price, price > 0 {
                    Text(price, format: .currency(code: "USD").precision(.fractionLength(0)))
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(Color.coral)
                }
                Spacer(minLength: 0)
                Button(action: { onAddToCart?() }) {
                    Image(systemName: "bag.badge.plus")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.coral)
                        .frame(width: 36, height: 32)
                        .background(Color.coralSoft)
                        .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.sm, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add \(product.title) to a cart")
            }
        }
        .padding(10)
    }

    private func openProduct() {
        guard let url = outboundURL else { return }
        OutboundRouter.open(url, postId: product.postId, source: "maxi") {
            browserTarget = BrowserTarget(url: $0)
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
