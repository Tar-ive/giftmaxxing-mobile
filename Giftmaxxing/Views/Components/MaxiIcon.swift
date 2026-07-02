import SwiftUI

struct MaxiIcon: View {
    var size: CGFloat = 32

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.coral, Color(hex: "#FF9A76")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)

            Text("🎁")
                .font(.system(size: size * 0.5))
        }
    }
}
