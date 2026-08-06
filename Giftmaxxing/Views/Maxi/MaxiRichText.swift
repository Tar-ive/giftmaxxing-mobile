import SwiftUI

// Maxi's replies rendered as text a person would want to read.
//
// The models emit light markdown — `**bold**`, `- ` bullets, numbered lists —
// and a plain `Text` printed the asterisks literally ("- **Flowers**: 15
// ideas"), which is the single most obvious "this is a raw LLM" tell in the
// app. SwiftUI's AttributedString markdown parser handles inline emphasis but
// not block structure, so lines are split first and bullets are drawn with a
// real hanging indent instead of a leading dash.
struct MaxiRichText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let value):
                    inline(value)
                case .bullet(let value):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                            .font(.bodyMedium)
                            .foregroundStyle(Color.coral)
                        inline(value)
                    }
                case .numbered(let index, let value):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(index).")
                            .font(.bodyMedium.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(Color.coral)
                        inline(value)
                    }
                case .spacer:
                    Color.clear.frame(height: 2)
                }
            }
        }
    }

    private func inline(_ value: String) -> some View {
        // `.inlineOnlyPreservingWhitespace` keeps the string intact and only
        // interprets emphasis — full markdown parsing would eat lone "*" and
        // stray brackets that appear in scraped product titles.
        let attributed = (try? AttributedString(
            markdown: value,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(value)

        return Text(attributed)
            .font(.bodyMedium)
            .fixedSize(horizontal: false, vertical: true)
    }

    private enum Block {
        case paragraph(String)
        case bullet(String)
        case numbered(Int, String)
        case spacer
    }

    private var blocks: [Block] {
        var out: [Block] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.isEmpty {
                // Collapse runs of blank lines; models love double spacing.
                if case .spacer = out.last { continue }
                if out.isEmpty { continue }
                out.append(.spacer)
                continue
            }

            if let match = line.firstMatch(of: /^(\d{1,2})[.)]\s+(.*)$/) {
                out.append(.numbered(Int(match.1) ?? 1, String(match.2)))
            } else if let match = line.firstMatch(of: /^[-*•]\s+(.*)$/) {
                out.append(.bullet(String(match.1)))
            } else {
                out.append(.paragraph(line))
            }
        }
        // A trailing spacer would add dead padding inside the bubble.
        if case .spacer = out.last { out.removeLast() }
        return out
    }
}
