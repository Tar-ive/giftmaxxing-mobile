import SwiftUI

@MainActor
final class MaxiViewModel: ObservableObject {
    @Published var messages: [MaxiMessage] = []
    @Published var inputText = ""
    @Published var isThinking = false

    private let api = APIClient.shared

    init() {
        messages.append(MaxiMessage(
            role: .assistant,
            text: "Hey! I'm Maxi, your AI gift concierge 🎁\n\nTell me who you're shopping for, their interests, or an occasion — I'll find the perfect gift.",
            products: [],
            steps: []
        ))
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
            let reply = try await api.askMaxi(
                userId: nil,
                name: nil,
                message: text,
                history: history
            )

            if let reply {
                let assistantMessage = MaxiMessage(
                    role: .assistant,
                    text: reply.say,
                    products: reply.pins,
                    steps: reply.steps
                )
                messages.append(assistantMessage)
            } else {
                messages.append(MaxiMessage(
                    role: .assistant,
                    text: "I'm having trouble connecting right now. Try again in a moment!"
                ))
            }
        } catch {
            messages.append(MaxiMessage(
                role: .assistant,
                text: "Something went wrong. Please try again."
            ))
        }

        isThinking = false
    }
}

struct MaxiView: View {
    @StateObject private var viewModel = MaxiViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.messages) { message in
                                MaxiMessageBubble(message: message)
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

                // Input
                HStack(spacing: 12) {
                    TextField("Ask Maxi anything...", text: $viewModel.inputText, axis: .vertical)
                        .font(.bodyMedium)
                        .lineLimit(1...4)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.cream)
                        .clipShape(RoundedRectangle(cornerRadius: 20))

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
            }
            .background(Color.surface)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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

    var body: some View {
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
