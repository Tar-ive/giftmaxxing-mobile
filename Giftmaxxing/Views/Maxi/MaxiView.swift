import SwiftUI

@MainActor
final class MaxiViewModel: ObservableObject {
    @Published var messages: [MaxiMessage] = []
    @Published var inputText = ""
    @Published var isThinking = false

    private let api = APIClient.shared
    private var catalog: [Post] = []

    init() {
        messages.append(MaxiMessage(
            role: .assistant,
            text: "Hey! I'm Maxi, your AI gift concierge 🎁\n\nTell me who you're shopping for, their interests, or an occasion — I'll find the perfect gift.",
            products: [],
            steps: [],
            chips: MaxiLocalEngine.seedChips
        ))
    }

    func send(_ text: String) {
        inputText = text
        Task { await sendMessage() }
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

        let userMessage = MaxiMessage(role: .user, text: text)
        messages.append(userMessage)
        inputText = ""
        isThinking = true

        let history = messages.dropLast().map { (role: $0.role.rawValue, text: $0.text) }

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
                messages.append(MaxiMessage(
                    role: .assistant,
                    text: reply.say,
                    products: reply.pins,
                    steps: reply.steps
                ))
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
        messages.append(MaxiMessage(
            role: .assistant,
            text: say,
            products: local.products,
            chips: local.chips
        ))
    }
}

struct MaxiView: View {
    @StateObject private var viewModel = MaxiViewModel()
    @StateObject private var speech = SpeechRecognizer()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
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
            }
        }
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
                    Text("🎁")
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
