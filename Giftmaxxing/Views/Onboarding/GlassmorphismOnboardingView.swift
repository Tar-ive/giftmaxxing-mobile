import SwiftUI

// Glassmorphism-style onboarding intro (DESIGN.md onboarding surface).
// Shown before ConsultView; tapping "Get Started" advances to the consult.
struct GlassmorphismOnboardingView: View {
    var onStart: () -> Void

    @State private var orbScale: CGFloat = 0.5
    @State private var orbOpacity: Double = 0
    @State private var glowScale: CGFloat = 0.3
    @State private var cardOpacity: Double = 0
    @State private var cardOffset: CGFloat = 30
    @State private var buttonOpacity: Double = 0
    @State private var buttonOffset: CGFloat = 20
    @State private var shimmer: CGFloat = -1

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.coral, .gradientEnd, .onboardingGlow, .onboardingWash],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [Color.onboardingGlow.opacity(0.5), .clear],
                center: .center,
                startRadius: 40,
                endRadius: 260
            )
            .frame(width: 520, height: 520)
            .offset(y: -100)
            .blur(radius: 20)

            VStack(spacing: 0) {
                Spacer()
                    .frame(height: 60)

                giftOrb

                Spacer()

                glassCard

                Spacer()

                startButton
                    .padding(.horizontal, ThemeSpacing.xl)
                    .padding(.bottom, 50)

                Spacer()
                    .frame(height: 8)
            }

            GeometryReader { geo in
                LinearShimmer(width: geo.size.width)
                    .opacity(0.15)
                    .offset(x: shimmer * geo.size.width)
            }
            .allowsHitTesting(false)
        }
        .onAppear { animateIn() }
    }

    private var giftOrb: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.6), .clear],
                        center: .center,
                        startRadius: 30,
                        endRadius: 160
                    )
                )
                .frame(width: 300, height: 300)
                .scaleEffect(glowScale)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.45), Color.white.opacity(0.15)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .background(Circle().fill(.ultraThinMaterial))
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.6), lineWidth: 1.5)
                )
                .frame(width: 180, height: 180)
                .shadow(color: Color.coral.opacity(0.35), radius: 30, y: 10)

            BrandGlyph(size: 56, tile: false)
                .font(.displayLarge)
        }
        .scaleEffect(orbScale)
        .opacity(orbOpacity)
    }

    private var glassCard: some View {
        VStack(spacing: ThemeSpacing.sm) {
            Text("Hey — I'm Maxi.")
                .font(.displayLarge)
                .foregroundStyle(.white)

            Text("I find gifts people actually keep.")
                .font(.bodyLarge.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.9))

            Text("This is the whole app — tell me about a person, I find the gift. Let's run your first consult now.")
                .font(.bodyMedium)
                .foregroundStyle(Color.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .padding(.horizontal, ThemeSpacing.xl)
                .lineSpacing(4)
        }
        .padding(.vertical, 36)
        .padding(.horizontal, ThemeSpacing.lg)
        .background {
            RoundedRectangle(cornerRadius: ThemeRadius.xl, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: ThemeRadius.xl, style: .continuous)
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )
        }
        .cardElevation()
        .padding(.horizontal, ThemeSpacing.xl)
        .opacity(cardOpacity)
        .offset(y: cardOffset)
    }

    private var startButton: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                buttonOpacity = 0
                buttonOffset = 20
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                onStart()
            }
        } label: {
            HStack(spacing: ThemeSpacing.xs) {
                Text("Get Started")
                    .font(.displaySmall)
                Image(systemName: "arrow.right")
                    .font(.bodyLarge.weight(.bold))
            }
            .foregroundStyle(Color.coral)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background {
                Capsule()
                    .fill(Color.surface)
                    .shadow(color: Color.coral.opacity(0.35), radius: 14, y: 6)
            }
        }
        .buttonStyle(.plain)
        .opacity(buttonOpacity)
        .offset(y: buttonOffset)
        .accessibilityLabel("Get Started with Maxi")
    }

    private func animateIn() {
        withAnimation(.easeOut(duration: 0.9)) {
            glowScale = 1.0
        }
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
            orbScale = 1.0
            orbOpacity = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            withAnimation(.easeOut(duration: 0.5)) {
                cardOpacity = 1
                cardOffset = 0
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                buttonOpacity = 1
                buttonOffset = 0
            }
        }
        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: false)) {
            shimmer = 2
        }
    }
}

private struct LinearShimmer: View {
    let width: CGFloat

    var body: some View {
        LinearGradient(
            colors: [.clear, .white, .clear],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: width * 0.4)
        .rotationEffect(.degrees(15))
        .blur(radius: 20)
    }
}
