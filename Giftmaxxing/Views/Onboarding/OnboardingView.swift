import SwiftUI

struct OnboardingPage: Identifiable {
    let id: Int
    var emoji: String
    var title: String
    var subtitle: String
    var grad: GradientStyle
}

struct OnboardingView: View {
    @Binding var isOnboardingComplete: Bool
    @State private var currentPage = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(id: 0, emoji: "🎁", title: "Never miss a gift", subtitle: "Track birthdays, anniversaries, and special occasions for everyone you care about.", grad: .coral),
        OnboardingPage(id: 1, emoji: "💡", title: "Discover perfect gifts", subtitle: "Swipe through curated finds, get AI recommendations from Maxi, and browse real products.", grad: .sky),
        OnboardingPage(id: 2, emoji: "👥", title: "Gift together", subtitle: "Create pools to split costs with friends. No more awkward Venmo requests.", grad: .lilac),
        OnboardingPage(id: 3, emoji: "✨", title: "Your AI concierge", subtitle: "Tell Maxi who you're shopping for and get instant, personalized gift suggestions.", grad: .sage),
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentPage) {
                ForEach(pages) { page in
                    VStack(spacing: 24) {
                        Spacer()

                        ZStack {
                            Circle()
                                .fill(Color.gradient(for: page.grad))
                                .frame(width: 160, height: 160)

                            Text(page.emoji)
                                .font(.system(size: 72))
                        }

                        VStack(spacing: 12) {
                            Text(page.title)
                                .font(.system(size: 28, weight: .heavy, design: .rounded))
                                .foregroundStyle(Color.ink)
                                .multilineTextAlignment(.center)

                            Text(page.subtitle)
                                .font(.system(size: 16))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }

                        Spacer()
                        Spacer()
                    }
                    .tag(page.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            // Bottom section
            VStack(spacing: 16) {
                Button(action: {
                    if currentPage < pages.count - 1 {
                        withAnimation {
                            currentPage += 1
                        }
                    } else {
                        isOnboardingComplete = true
                    }
                }) {
                    Text(currentPage == pages.count - 1 ? "Get started" : "Next")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.coral)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                if currentPage < pages.count - 1 {
                    Button("Skip") {
                        isOnboardingComplete = true
                    }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .background(Color.surface)
    }
}
