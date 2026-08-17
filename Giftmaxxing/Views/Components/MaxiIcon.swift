import SwiftUI

// Maxi's mark: a four-point spark with concave sides — the shape people now
// read as "intelligence" — drawn as a real Shape rather than an SF Symbol or
// an emoji, per DESIGN.md (custom marks are Shape-conforming and scale
// cleanly; emoji-as-logo is deprecated).
//
// This replaces the gift-box glyph the avatar used to borrow from the app
// logo. Two problems with that: it made the assistant look like the app rather
// than a character in it, and the floating button already used a spark — so
// you tapped one mark and were answered by a different one.
struct SparkleMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let p = { (x: CGFloat, y: CGFloat) in
            CGPoint(x: rect.minX + x * w, y: rect.minY + y * h)
        }
        // Waist controls how sharp the points read. 0.40/0.60 keeps them
        // crisp at 24pt without turning into needles at 56pt.
        let near: CGFloat = 0.40
        let far: CGFloat = 0.60

        path.move(to: p(0.5, 0))
        path.addQuadCurve(to: p(1, 0.5), control: p(far, near))
        path.addQuadCurve(to: p(0.5, 1), control: p(far, far))
        path.addQuadCurve(to: p(0, 0.5), control: p(near, far))
        path.addQuadCurve(to: p(0.5, 0), control: p(near, near))
        path.closeSubpath()
        return path
    }
}

// The avatar beside every Maxi reply, and the glyph inside the floating button.
struct MaxiIcon: View {
    var size: CGFloat = 32
    /// Draws the gradient disc behind the mark. Off when the mark sits on a
    /// coral surface already (the FAB).
    var showsBackground: Bool = true

    var body: some View {
        ZStack {
            if showsBackground {
                Circle()
                    .fill(Color.brandGradient)
                    .frame(width: size, height: size)
            }

            // A big spark with a small companion reads as a character; one
            // centred spark reads as a loading state.
            SparkleMark()
                .fill(showsBackground ? AnyShapeStyle(Color.onPrimary) : AnyShapeStyle(Color.onPrimary))
                .frame(width: size * 0.46, height: size * 0.46)
                .offset(x: -size * 0.05, y: -size * 0.02)

            SparkleMark()
                .fill(Color.onPrimary.opacity(0.85))
                .frame(width: size * 0.2, height: size * 0.2)
                .offset(x: size * 0.21, y: size * 0.19)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

#Preview {
    HStack(spacing: 16) {
        MaxiIcon(size: 28)
        MaxiIcon(size: 40)
        MaxiIcon(size: 56)
    }
    .padding()
    .background(Color.cream)
}
