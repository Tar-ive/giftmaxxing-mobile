import SwiftUI

// Activity / notifications feed — iOS port of web/app/feed/activity/page.tsx.
// Completed challenge connections (from the invite flow) surface at the top,
// followed by the same demo social activity the web app ships.
struct ActivityItem: Identifiable {
    enum Kind { case maxi, drop, pool, like, connection, follow, milestone, challenge }
    let id = UUID()
    let kind: Kind
    let text: String
    let time: String
    var user: String?
}

struct ActivityView: View {
    @State private var items: [ActivityItem] = ActivityView.demoItems

    var body: some View {
        List {
            ForEach(items) { item in
                ActivityRow(item: item)
                    .listRowBackground(Color.surface)
                    .listRowSeparatorTint(Color.line)
            }
        }
        .listStyle(.plain)
        .background(Color.surface)
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            AnalyticsEngine.shared.trackScreenView(screen: "activity")
        }
    }

    // Mirror of the web DEMO_ITEMS list.
    static let demoItems: [ActivityItem] = [
        ActivityItem(kind: .maxi, text: "Maya's birthday is in 4 days — I lined up 7 ideas in your budget.", time: "now"),
        ActivityItem(kind: .drop, text: "Perfume on your radar just dropped 20%. Snag it before it's gone.", time: "2h"),
        ActivityItem(kind: .pool, text: "chipped in $25 to Sam's farewell gift. 6 of 9 in!", time: "3h", user: "jules"),
        ActivityItem(kind: .like, text: "and 12 others liked your find.", time: "5h", user: "theo"),
        ActivityItem(kind: .connection, text: "claimed something from your wishlist", time: "1d", user: "noor"),
        ActivityItem(kind: .follow, text: "started following your lists.", time: "2d", user: "ivy"),
        ActivityItem(kind: .milestone, text: "You completed \"Read 12 books\" — $50 reward unlocked! Treat yourself.", time: "3d"),
        ActivityItem(kind: .pool, text: "added $15 to Noor's birthday pool. Almost there!", time: "4d", user: "remy"),
        ActivityItem(kind: .like, text: "saved your gift idea for Theo.", time: "5d", user: "maya"),
    ]
}

private struct ActivityRow: View {
    let item: ActivityItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            icon

            VStack(alignment: .leading, spacing: 2) {
                Group {
                    if let user = item.user {
                        Text(SocialUsers.name(for: user).components(separatedBy: " ").first ?? user)
                            .fontWeight(.bold)
                        + Text(" \(item.text)")
                    } else {
                        Text(item.text)
                    }
                }
                .font(.system(size: 14))
                .foregroundStyle(Color.ink)
                .fixedSize(horizontal: false, vertical: true)

                Text(item.time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var icon: some View {
        switch item.kind {
        case .maxi, .challenge:
            iconCircle(emoji: "🎁", background: Color.coral)
        case .milestone:
            iconCircle(emoji: "🏆", background: Color(hex: "#D1FAE5"))
        case .drop:
            ZStack {
                Circle().fill(Color.coralSoft)
                Image(systemName: "chart.line.downtrend.xyaxis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.coral)
            }
            .frame(width: 44, height: 44)
        case .pool:
            iconCircle(emoji: "💰", background: Color(hex: "#E0F2FE"))
        case .like, .connection, .follow:
            if let user = item.user {
                AvatarView(name: SocialUsers.name(for: user), grad: SocialUsers.grad(for: user), size: 44)
            } else {
                iconCircle(emoji: "❤️", background: Color.coralSoft)
            }
        }
    }

    private func iconCircle(emoji: String, background: Color) -> some View {
        ZStack {
            Circle().fill(background)
            Text(emoji).font(.system(size: 18))
        }
        .frame(width: 44, height: 44)
    }
}
