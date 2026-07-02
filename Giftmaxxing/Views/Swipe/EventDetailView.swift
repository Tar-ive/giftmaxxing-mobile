import SwiftUI

// Event detail — what tapping an event row opens (web parity: an event links
// to gift ideas + group-gift actions instead of being a dead row).
struct EventDetailView: View {
    let event: GiftEvent
    @EnvironmentObject private var appState: AppState

    private var urgencyColor: Color {
        let days = event.daysUntil
        if days <= 3 { return .red }
        if days <= 7 { return .orange }
        if days <= 14 { return Color.coral }
        return .secondary
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Hero
                VStack(spacing: 12) {
                    Text(event.eventTypeIcon)
                        .font(.system(size: 56))
                        .frame(width: 96, height: 96)
                        .background(Color.cream)
                        .clipShape(RoundedRectangle(cornerRadius: 24))

                    Text(event.title)
                        .font(.displayMedium)
                        .foregroundStyle(Color.ink)
                        .multilineTextAlignment(.center)

                    Text(event.dateString)
                        .font(.bodyMedium)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 6) {
                        Text("\(event.daysUntil)")
                            .font(.system(size: 24, weight: .heavy, design: .rounded))
                            .foregroundStyle(urgencyColor)
                        Text(event.daysUntil == 1 ? "day away" : "days away")
                            .font(.bodyMedium)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.cream)
                    .clipShape(Capsule())
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 12)

                // Facts
                VStack(spacing: 0) {
                    if !event.recipientName.isEmpty {
                        factRow(icon: "person.fill", label: "For", value: event.recipientName)
                        Divider().padding(.leading, 44)
                    }
                    factRow(icon: "tag.fill", label: "Occasion", value: event.type.replacingOccurrences(of: "_", with: " ").capitalized)
                    if let budget = event.budget {
                        Divider().padding(.leading, 44)
                        factRow(icon: "dollarsign.circle.fill", label: "Budget", value: "$\(Int(budget))")
                    }
                    if let notes = event.notes, !notes.isEmpty {
                        Divider().padding(.leading, 44)
                        factRow(icon: "note.text", label: "Notes", value: notes)
                    }
                }
                .background(Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.04), radius: 6, y: 2)

                // Actions
                VStack(spacing: 10) {
                    Button {
                        appState.selectedTab = .swipe
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                            Text("Swipe gift ideas\(event.recipientName.isEmpty ? "" : " for \(event.recipientName.components(separatedBy: " ").first ?? "")")")
                                .lineLimit(1)
                        }
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.coral)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    NavigationLink {
                        PoolsView()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "person.2.fill")
                            Text("Start a group gift")
                        }
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.coral)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.coralSoft)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    NavigationLink {
                        ChallengeView()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "paperplane.fill")
                            Text("Send them a swipe challenge")
                        }
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.cream)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
            .padding(16)
        }
        .background(Color.surface)
        .navigationTitle("Event")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            AnalyticsEngine.shared.trackScreenView(screen: "event_detail")
        }
    }

    private func factRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(Color.coral)
                .frame(width: 32, height: 32)
                .background(Color.coralSoft)
                .clipShape(Circle())

            Text(label)
                .font(.bodyMedium)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.ink)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}
