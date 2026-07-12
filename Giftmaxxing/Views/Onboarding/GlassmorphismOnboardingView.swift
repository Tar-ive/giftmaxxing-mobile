import SwiftUI

// Glassmorphism-style onboarding intro inspired by a Figma community design.
// Replaces the sun orb with a gift icon and uses Maxi's onboarding copy.
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
            // Warm gradient background
            LinearGradient(
                colors: [
                    Color(hex: "#FB6F52"),
                    Color(hex: "#FF9A76"),
                    Color(hex: "#FFC5A0"),
                    Color(hex: "#FFF9F5"),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Secondary ambient glow
            RadialGradient(
                colors: [Color(hex: "#FFD4B8").opacity(0.5), .clear],
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

                // Gift orb (replaces the sun)
                giftOrb

                Spacer()

                // Frosted glass card
                glassCard

                Spacer()

                // Get Started button
                startButton
                    .padding(.horizontal, 28)
                    .padding(.bottom, 50)

                Spacer()
                    .frame(height: 8)
            }

            // Shimmer sweep
            GeometryReader { geo in
                LinearShimmer(width: geo.size.width)
                    .opacity(0.15)
                    .offset(x: shimmer * geo.size.width)
            }
            .allowsHitTesting(false)
        }
        .onAppear {
            animateIn()
            // TEMP: auto-advance after 3s for screenshot capture
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                withAnimation(.easeOut(duration: 0.45)) {
                    onStart()
                }
            }
        }
    }

    // MARK: - Gift orb

    private var giftOrb: some View {
        ZStack {
            // Outer glow
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

            // Main orb circle — frosted glass
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.45), Color.white.opacity(0.15)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .background(
                    Circle().fill(.ultraThinMaterial)
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.6), lineWidth: 1.5)
                )
                .frame(width: 180, height: 180)
                .shadow(color: Color(hex: "#FB6F52").opacity(0.35), radius: 30, y: 10)

            // Gift icon
            VStack(spacing: 4) {
                Text("🎁")
                    .font(.system(size: 64))
            }
        }
        .scaleEffect(orbScale)
        .opacity(orbOpacity)
    }

    // MARK: - Glass card

    private var glassCard: some View {
        VStack(spacing: 14) {
            Text("Hey — I'm Maxi.")
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)

            Text("I find gifts people actually keep.")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.9))

            Text("This is the whole app — tell me about a person, I find the gift. Let's run your first consult now.")
                .font(.system(size: 14))
                .foregroundStyle(Color.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .lineSpacing(4)
        }
        .padding(.vertical, 36)
        .padding(.horizontal, 20)
        .background {
            RoundedRectangle(cornerRadius: 28)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 28)
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )
        }
        .shadow(color: Color.black.opacity(0.12), radius: 20, y: 8)
        .padding(.horizontal, 28)
        .opacity(cardOpacity)
        .offset(y: cardOffset)
    }

    // MARK: - Start button

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
            HStack(spacing: 8) {
                Text("Get Started")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Image(systemName: "arrow.right")
                    .font(.system(size: 16, weight: .bold))
            }
            .foregroundStyle(Color(hex: "#FB6F52"))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background {
                Capsule()
                    .fill(Color.white)
                    .shadow(color: Color(hex: "#FB6F52").opacity(0.35), radius: 14, y: 6)
            }
        }
        .opacity(buttonOpacity)
        .offset(y: buttonOffset)
    }

    // MARK: - Animations

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

// Diagonal shimmer sweep overlay
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