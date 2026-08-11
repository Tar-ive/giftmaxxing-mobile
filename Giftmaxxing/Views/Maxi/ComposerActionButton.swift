import SwiftUI

// The composer's single action button.
//
// Contextual action swapping: one control whose meaning follows the state of
// the field rather than two controls competing for the same job. Empty field →
// voice. Something typed → send. Recording → stop. Only one of those is ever
// the right move, so only one is ever offered.
//
// The transition is the affordance: the glyph cross-fades and the tint travels
// from quiet to brand, so the change reads as the SAME button transforming
// rather than one button being swapped for another. `contentTransition` +
// matched frame keep it from jumping.
struct ComposerActionButton: View {
    enum Mode: Equatable {
        case voice
        case send
        case stopRecording
    }

    let mode: Mode
    var onVoice: () -> Void
    var onSend: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var symbol: String {
        switch mode {
        case .voice: return "mic.fill"
        case .send: return "arrow.up"
        case .stopRecording: return "stop.fill"
        }
    }

    private var fill: Color {
        switch mode {
        // Quiet until there is something to do — an always-bright button that
        // does nothing is noise.
        case .voice: return Color.ink.opacity(0.08)
        case .send: return Color.coral
        case .stopRecording: return .red
        }
    }

    private var tint: Color {
        mode == .voice ? Color.inkSecondary : .white
    }

    private var label: String {
        switch mode {
        case .voice: return "Speak to Maxi"
        case .send: return "Send"
        case .stopRecording: return "Stop recording"
        }
    }

    var body: some View {
        Button {
            switch mode {
            case .voice, .stopRecording: onVoice()
            case .send: onSend()
            }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: mode == .send ? 17 : 16, weight: .bold))
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 36, height: 36)
                .background(fill, in: Circle())
                // A recording button that looks identical to an idle one is a
                // trap — the ring makes "live" unmistakable.
                .overlay {
                    if mode == .stopRecording {
                        Circle().strokeBorder(.red.opacity(0.35), lineWidth: 3)
                            .scaleEffect(1.25)
                    }
                }
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: mode)
        .sensoryFeedback(.selection, trigger: mode)
        .accessibilityLabel(label)
    }
}
