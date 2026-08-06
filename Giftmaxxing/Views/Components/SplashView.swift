import SwiftUI

// Amazon-style cold-launch splash: brand logo scales in with a spring, holds
// a beat, then the overlay fades out (driven by ContentView).
struct SplashView: View {
    var onFinished: () -> Void

    @State private var logoScale: CGFloat = 0.7
    @State private var logoOpacity: Double = 0
    @State private var glowScale: CGFloat = 0.4

    var body: some View {
        ZStack {
            Color.cream.ignoresSafeArea()

            // Soft radial glow behind the logo
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.coral.opacity(0.25), .clear],
                        center: .center,
                        startRadius: 10,
                        endRadius: 180
                    )
                )
                .frame(width: 360, height: 360)
                .scaleEffect(glowScale)

            VStack(spacing: 16) {
                Image("LaunchLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 156, height: 156)
                    .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                    .shadow(color: Color.coral.opacity(0.22), radius: 24, y: 10)
                    .scaleEffect(logoScale)

                Text("giftmaxxing")
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.coral)

                Text("gifting, solved")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .opacity(logoOpacity)
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.65)) {
                logoScale = 1.0
                logoOpacity = 1
            }
            withAnimation(.easeOut(duration: 0.9)) {
                glowScale = 1.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.15) {
                onFinished()
            }
        }
    }
}
