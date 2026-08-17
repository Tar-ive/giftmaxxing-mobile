import SwiftUI
import GiftmaxxingDesignSystem

// "Upcoming celebrations" — replaces the 31-day month grid.
//
// A monthly calendar is the wrong instrument for this job. Gifting dates are
// sparse (a handful a year) and usually months out, so the grid was ~28 empty
// cells around two dots, and it had to jump to July 2027 to show anything at
// all. Worse, it answered "what does this month look like?" when the only
// question anyone brings to this screen is "what's next, and how long have I
// got?"
//
// A chronological carousel answers exactly that, in one row, with no month to
// navigate.
struct UpcomingCelebrationsRail: View {
    let moments: [TimelineMoment]
    var onSelect: (TimelineMoment) -> Void
    var onAddDate: () -> Void

    private var upcoming: [TimelineMoment] {
        moments
            .filter { $0.days >= 0 }
            .sorted { $0.date < $1.date }
            .dedupedByPerson()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ThemeSpacing.xs) {
            HStack {
                SectionHeader("Upcoming celebrations")
                Spacer()
                Button(action: onAddDate) {
                    Label("Add", systemImage: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.coral)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)

            if upcoming.isEmpty {
                Button(action: onAddDate) {
                    HStack(spacing: 10) {
                        Image(systemName: "calendar.badge.plus")
                            .font(.title3)
                            .foregroundStyle(Color.coral)
                        Text("Add a birthday so nothing sneaks up on you")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.ink)
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .background(Color.surfaceSunken)
                    .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.lg, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: ThemeSpacing.sm) {
                        ForEach(upcoming.prefix(12)) { moment in
                            Button { onSelect(moment) } label: {
                                CelebrationCard(moment: moment)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

private struct CelebrationCard: View {
    let moment: TimelineMoment

    // Urgency earns colour. Everything is months away most of the year, so
    // painting every card coral would make the one that matters invisible.
    private var isSoon: Bool { moment.days <= 14 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: moment.emoji)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isSoon ? Color.onPrimary : Color.coral)
                    .frame(width: 30, height: 30)
                    .background(isSoon ? Color.coral : Color.coralSoft, in: Circle())
                Spacer(minLength: 0)
                Text(countdown)
                    .font(.system(size: 11, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(isSoon ? Color.coral : Color.inkSecondary)
            }

            Text(moment.title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Text(moment.sourceLabel)
                .font(.system(size: 11))
                .foregroundStyle(Color.inkTertiary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(width: 168, height: 132, alignment: .topLeading)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ThemeRadius.lg, style: .continuous)
                .strokeBorder(isSoon ? Color.coral.opacity(0.45) : Color.line, lineWidth: 1)
        }
    }

    /// Today / Tomorrow / "in 5 days" / "in 3 weeks" / "in 7 months".
    private var countdown: String {
        switch moment.days {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case 2...13: return "in \(moment.days) days"
        case 14...30: return "in \(moment.days / 7) weeks"
        default:
            let months = max(1, Int((Double(moment.days) / 30.44).rounded()))
            return months == 1 ? "in a month" : "in \(months) months"
        }
    }
}
