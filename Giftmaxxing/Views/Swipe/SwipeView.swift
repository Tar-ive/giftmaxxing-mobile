import SwiftUI

@MainActor
final class SwipeViewModel: ObservableObject {
    @Published var cards: [Post] = []
    @Published var currentIndex = 0
    @Published var isLoading = false
    @Published var yesCount = 0
    @Published var noCount = 0
    @Published var offset: CGSize = .zero
    @Published var isSwiping = false

    private let api = APIClient.shared

    var currentCard: Post? {
        guard currentIndex < cards.count else { return nil }
        return cards[currentIndex]
    }

    var isFinished: Bool {
        currentIndex >= cards.count && !cards.isEmpty
    }

    func loadCards() async {
        guard !isLoading else { return }
        isLoading = true

        do {
            let page = try await api.fetchRecommendations(limit: 30)
            cards = page.posts
            currentIndex = 0
            yesCount = 0
            noCount = 0
        } catch {
            // use empty state
        }

        isLoading = false
    }

    func swipeRight() {
        guard !isSwiping, currentIndex < cards.count else { return }
        isSwiping = true
        yesCount += 1
        let card = cards[currentIndex]
        Task { await api.recordInteraction(userId: nil, targetId: card.id, type: "like") }
        withAnimation(.spring(response: 0.4)) {
            offset = CGSize(width: 500, height: 0)
        }
        advanceAfterDelay()
    }

    func swipeLeft() {
        guard !isSwiping, currentIndex < cards.count else { return }
        isSwiping = true
        noCount += 1
        withAnimation(.spring(response: 0.4)) {
            offset = CGSize(width: -500, height: 0)
        }
        advanceAfterDelay()
    }

    private func advanceAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.currentIndex += 1
            self?.offset = .zero
            self?.isSwiping = false
        }
    }
}

struct SwipeView: View {
    @StateObject private var viewModel = SwipeViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if viewModel.isLoading {
                    Spacer()
                    ProgressView("Loading gifts...")
                        .font(.bodyMedium)
                    Spacer()
                } else if viewModel.isFinished {
                    SwipeCompleteView(
                        yesCount: viewModel.yesCount,
                        noCount: viewModel.noCount,
                        onRestart: {
                            Task { await viewModel.loadCards() }
                        }
                    )
                } else if let card = viewModel.currentCard {
                    // Progress
                    HStack(spacing: 4) {
                        Text("\(viewModel.currentIndex + 1)/\(viewModel.cards.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        HStack(spacing: 8) {
                            Label("\(viewModel.yesCount)", systemImage: "heart.fill")
                                .font(.caption)
                                .foregroundStyle(Color.coral)
                            Label("\(viewModel.noCount)", systemImage: "xmark")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    // Card
                    Spacer()

                    SwipeCardView(post: card)
                        .offset(viewModel.offset)
                        .rotationEffect(.degrees(Double(viewModel.offset.width) / 20))
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    viewModel.offset = value.translation
                                }
                                .onEnded { value in
                                    if value.translation.width > 100 {
                                        viewModel.swipeRight()
                                    } else if value.translation.width < -100 {
                                        viewModel.swipeLeft()
                                    } else {
                                        withAnimation(.spring(response: 0.3)) {
                                            viewModel.offset = .zero
                                        }
                                    }
                                }
                        )

                    Spacer()

                    // Action buttons
                    HStack(spacing: 40) {
                        Button(action: { viewModel.swipeLeft() }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(.red)
                                .frame(width: 64, height: 64)
                                .background(Color.surface)
                                .clipShape(Circle())
                                .shadow(color: .red.opacity(0.2), radius: 8)
                        }
                        .disabled(viewModel.isSwiping)

                        Button(action: { viewModel.swipeRight() }) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(Color.coral)
                                .frame(width: 64, height: 64)
                                .background(Color.surface)
                                .clipShape(Circle())
                                .shadow(color: Color.coral.opacity(0.3), radius: 8)
                        }
                        .disabled(viewModel.isSwiping)
                    }
                    .padding(.bottom, 24)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "rectangle.portrait.on.rectangle.portrait.slash")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("No gifts to swipe")
                            .font(.displaySmall)
                        Button("Load gifts") {
                            Task { await viewModel.loadCards() }
                        }
                        .font(.labelBold)
                        .foregroundStyle(Color.coral)
                    }
                }
            }
            .background(Color.cream)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Swipe")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {}) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.coral)
                    }
                }
            }
        }
        .task {
            if viewModel.cards.isEmpty {
                await viewModel.loadCards()
            }
        }
    }
}

struct SwipeCardView: View {
    let post: Post

    var body: some View {
        VStack(spacing: 0) {
            // Product image
            ZStack {
                Color.gradient(for: post.product.grad)

                Text(post.product.emoji)
                    .font(.system(size: 72))

                if let image = post.product.image, let url = URL(string: image) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        }
                    }
                }
            }
            .frame(height: 340)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24))

            // Info
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(post.product.name)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.ink)
                    Spacer()
                    Text("$\(Int(post.product.price))")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.coral)
                }

                Text(post.product.brand)
                    .font(.bodyMedium)
                    .foregroundStyle(.secondary)

                if !post.caption.isEmpty {
                    Text(post.caption)
                        .font(.bodyMedium)
                        .foregroundStyle(Color.ink)
                        .lineLimit(3)
                }

                if let reason = post.reason {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12))
                        Text(reason)
                            .font(.caption)
                    }
                    .foregroundStyle(Color.coral)
                    .padding(.top, 4)
                }
            }
            .padding(20)
            .background(Color.surface)
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 24, bottomTrailingRadius: 24))
        }
        .shadow(color: .black.opacity(0.1), radius: 16, y: 8)
        .padding(.horizontal, 20)
    }
}

struct SwipeCompleteView: View {
    let yesCount: Int
    let noCount: Int
    var onRestart: (() -> Void)?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(Color.coral)

            Text("All done!")
                .font(.displayLarge)
                .foregroundStyle(Color.ink)

            Text("You liked \(yesCount) gifts out of \(yesCount + noCount)")
                .font(.bodyLarge)
                .foregroundStyle(.secondary)

            HStack(spacing: 24) {
                VStack(spacing: 4) {
                    Text("\(yesCount)")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Color.coral)
                    Text("Liked")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 4) {
                    Text("\(noCount)")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text("Passed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 20)

            Button(action: { onRestart?() }) {
                Text("Swipe again")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.coral)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 40)

            Spacer()
        }
    }
}
