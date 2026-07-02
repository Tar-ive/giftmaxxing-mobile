import SwiftUI

// Full-screen story viewer — iOS port of the web StoryViewer
// (web/components/app/stories.tsx): segmented progress bars, auto-advance,
// tap left/right to navigate, swipe down to dismiss.
struct StoryViewerView: View {
    let stories: [StoryItem]
    @State var index: Int

    @Environment(\.dismiss) private var dismiss
    @State private var progress: Double = 0
    @State private var timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    private let storyDuration: Double = 4.0

    private var story: StoryItem { stories[index] }

    var body: some View {
        ZStack {
            Color.gradient(for: story.grad)
                .ignoresSafeArea()

            // Content
            VStack(spacing: 20) {
                Spacer()

                AvatarView(name: story.user, grad: story.grad, size: 96)
                    .overlay(
                        Circle().strokeBorder(.white.opacity(0.8), lineWidth: 3)
                    )

                Text(story.label)
                    .font(.displayMedium)
                    .foregroundStyle(Color.ink)

                if let countdown = story.countdown {
                    Text("\(countdown) away")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.coral)
                        .clipShape(Capsule())
                }

                storyMessage

                Spacer()
            }
            .padding(24)

            // Tap zones
            HStack(spacing: 0) {
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { previous() }
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { next() }
            }
            .ignoresSafeArea()

            // Chrome
            VStack {
                // Progress bars
                HStack(spacing: 4) {
                    ForEach(stories.indices, id: \.self) { i in
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.white.opacity(0.35))
                                Capsule()
                                    .fill(.white)
                                    .frame(width: geo.size.width * barFill(for: i))
                            }
                        }
                        .frame(height: 3)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)

                HStack(spacing: 10) {
                    AvatarView(name: story.user, grad: story.grad, size: 32)
                    Text(story.user)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.ink)
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Color.ink)
                            .padding(8)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 6)

                Spacer()
            }
        }
        .onReceive(timer) { _ in
            progress += 0.05 / storyDuration
            if progress >= 1 { next() }
        }
        .onChange(of: index) { _, _ in progress = 0 }
    }

    @ViewBuilder
    private var storyMessage: some View {
        switch story.kind {
        case "birthday":
            storyChip(icon: "gift.fill", text: "Birthday coming up — find the perfect gift")
        case "event":
            storyChip(icon: "calendar", text: "Event gift ideas are trending")
        case "drop":
            storyChip(icon: "chart.line.downtrend.xyaxis", text: "Price drops on items you follow")
        case "anniv":
            storyChip(icon: "heart.fill", text: "Anniversary — warm tones only")
        case "list":
            storyChip(icon: "list.star", text: "Updated their wishlist")
        default:
            storyChip(icon: "sparkles", text: "Tap through for gift inspiration")
        }
    }

    private func storyChip(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14))
            Text(text)
                .font(.system(size: 14, weight: .semibold))
        }
        .foregroundStyle(Color.ink)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.white.opacity(0.75))
        .clipShape(Capsule())
    }

    private func barFill(for i: Int) -> Double {
        if i < index { return 1 }
        if i == index { return progress }
        return 0
    }

    private func next() {
        if index < stories.count - 1 {
            index += 1
        } else {
            dismiss()
        }
    }

    private func previous() {
        if progress > 0.2 {
            progress = 0
        } else if index > 0 {
            index -= 1
        }
    }
}
