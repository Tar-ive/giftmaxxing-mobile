import SwiftUI

struct StoryItem: Identifiable {
    let id: String
    var user: String
    var label: String
    var countdown: String?
    var isAdd: Bool
    var isLive: Bool
    var kind: String?
    var grad: GradientStyle

    static let samples: [StoryItem] = [
        StoryItem(id: "s_you", user: "You", label: "Your story", isAdd: true, isLive: false, grad: .coral),
        StoryItem(id: "s_drop", user: "Drops", label: "Drops", isAdd: false, isLive: true, kind: "drop", grad: .coral),
        StoryItem(id: "s_maya", user: "Maya", label: "Maya · 4d", countdown: "4d", isAdd: false, isLive: false, kind: "birthday", grad: .rose),
        StoryItem(id: "s_sam", user: "Sam", label: "Sam farewell", isAdd: false, isLive: false, kind: "event", grad: .sky),
        StoryItem(id: "s_noor", user: "Noor", label: "Noor · 11d", countdown: "11d", isAdd: false, isLive: false, kind: "birthday", grad: .butter),
        StoryItem(id: "s_theo", user: "Theo", label: "Theo", isAdd: false, isLive: false, kind: "list", grad: .sage),
        StoryItem(id: "s_ivy", user: "Ivy", label: "Ivy · 18d", countdown: "18d", isAdd: false, isLive: false, kind: "anniv", grad: .rose),
    ]
}

struct StoriesTray: View {
    let stories: [StoryItem]

    init(stories: [StoryItem] = StoryItem.samples) {
        self.stories = stories
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(stories) { story in
                    StoryBubble(story: story)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }
}

struct StoryBubble: View {
    let story: StoryItem

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                // Ring
                Circle()
                    .strokeBorder(
                        story.isLive
                            ? LinearGradient(colors: [.coral, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
                            : Color.gradient(for: story.grad),
                        lineWidth: 2.5
                    )
                    .frame(width: 68, height: 68)

                // Avatar
                AvatarView(name: story.user, grad: story.grad, size: 60)

                // Add button
                if story.isAdd {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(Color.coral)
                                .background(Circle().fill(Color.surface).frame(width: 18, height: 18))
                        }
                    }
                    .frame(width: 68, height: 68)
                }

                // Live badge
                if story.isLive {
                    VStack {
                        Spacer()
                        Text("LIVE")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                LinearGradient(colors: [.coral, .red], startPoint: .leading, endPoint: .trailing)
                            )
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.surface, lineWidth: 2))
                    }
                }

                // Countdown badge
                if let countdown = story.countdown {
                    VStack {
                        HStack {
                            Text(countdown)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.coral)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(Color.surface, lineWidth: 1.5))
                            Spacer()
                        }
                        Spacer()
                    }
                    .frame(width: 68, height: 68)
                }
            }

            Text(story.label)
                .font(.system(size: 11))
                .foregroundStyle(Color.ink)
                .lineLimit(1)
                .frame(width: 72)
        }
    }
}
