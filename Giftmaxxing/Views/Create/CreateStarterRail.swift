import SwiftUI

// What the Create tab leads with, per design variant.
//
// An empty Create tab currently asks one question — "choose photos or a video" —
// which is the hardest possible first step: it demands you already know what
// you're making. Each variant answers that differently, and which answer gets
// people to actually post is the thing worth measuring:
//
//   A · Camera gallery   — jump straight to a source. Fastest for someone who
//                          already has the shot. The control.
//   B · Post inspiration — show what a good gift post looks like first, so the
//                          blank page is pre-filled with a format to copy.
//   C · Templates        — testimonial prompts and song-backed formats: the
//                          most structure, least blank-page anxiety, but the
//                          most steps before a first post exists.
struct CreateStarterRail: View {
    let focus: DesignVariant.CreateFocus
    /// Opens the existing photo / video / camera source picker.
    var onPickMedia: () -> Void
    /// A template or prompt was chosen — carried into the caption field.
    var onUseTemplate: (String) -> Void

    var body: some View {
        switch focus {
        case .cameraGallery:
            EmptyView()   // Variant A keeps today's single picker, unchanged.
        case .postInspiration:
            inspirationRail
        case .templates:
            templateRail
        }
    }

    // MARK: - B · Post inspiration

    private static let inspiration: [(symbol: String, title: String, prompt: String)] = [
        ("shippingbox.fill", "Unboxing", "The moment they opened it —"),
        ("hands.sparkles.fill", "Their reaction", "I wish I'd filmed their face when"),
        ("checklist", "What I bought and why", "Here's what I got and the thinking behind it:"),
        ("sparkles", "The wrap", "Spent longer on the wrapping than the gift:"),
    ]

    private var inspirationRail: some View {
        section("Templates") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: ThemeSpacing.sm) {
                    ForEach(Self.inspiration, id: \.title) { item in
                        Button {
                            onUseTemplate(item.prompt)
                            onPickMedia()
                        } label: {
                            starterTile(symbol: item.symbol, title: item.title)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    // MARK: - C · Templates

    private static let templates: [(symbol: String, title: String, prompt: String)] = [
        ("quote.bubble.fill", "Testimonial", "Honest review of the gift I gave:"),
        ("music.note", "Song moment", "This song + this gift ="),
        ("person.2.fill", "Duet a reaction", "Their reaction, on repeat:"),
        ("list.number", "Top 3", "My top 3 gifts this year:"),
        ("clock.arrow.circlepath", "Before / after", "How it started vs how it landed:"),
    ]

    private var templateRail: some View {
        section("Templates") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: ThemeSpacing.sm) {
                    ForEach(Self.templates, id: \.title) { item in
                        Button {
                            onUseTemplate(item.prompt)
                            onPickMedia()
                        } label: {
                            starterTile(symbol: item.symbol, title: item.title, tall: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    // MARK: - Shared

    // One header, one weight. The screen previously stacked a nav title, a
    // section title and a helper line before you reached anything tappable.
    @ViewBuilder
    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: ThemeSpacing.xs) {
            SectionHeader(title)
            content()
        }
    }

    private func starterTile(symbol: String, title: String, tall: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.coral)
            Spacer(minLength: 0)
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(ThemeSpacing.sm)
        .frame(width: 116, height: tall ? 116 : 96, alignment: .topLeading)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ThemeRadius.lg, style: .continuous)
                .strokeBorder(Color.line, lineWidth: 1)
        }
    }
}
