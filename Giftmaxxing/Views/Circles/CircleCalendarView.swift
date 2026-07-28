import SwiftUI

// Google-Calendar-style month grid for Circles. One calendar, many sources:
// the chip row toggles "Me" (your own milestones) and each circle you're in,
// and only the selected sources populate the grid. Tapping a day shows that
// day's moments underneath — no more scrolling a long list to find a date.
struct CircleCalendarView: View {
    let moments: [TimelineMoment]
    /// Sources the user can toggle: ("me", "Me") plus (circleId, circleName).
    let sources: [CalendarSource]
    var onSelectMoment: (TimelineMoment) -> Void
    var onAddDate: () -> Void

    struct CalendarSource: Identifiable, Equatable {
        let id: String
        let name: String
        let emoji: String?
    }

    @State private var visibleMonth = Calendar.current.startOfDay(for: Date())
    @State private var selectedDay: Date?
    @State private var hiddenSources: Set<String> = []

    private let calendar = Calendar.current

    private var shownMoments: [TimelineMoment] {
        moments.filter { !hiddenSources.contains(sourceId(for: $0)) }
    }

    private func sourceId(for moment: TimelineMoment) -> String {
        switch moment.kind {
        case .personal: return "me"
        case .circle(let circleId): return circleId
        }
    }

    // Color-code by source so a glance at the grid says whose day it is.
    private func tint(for moment: TimelineMoment) -> Color {
        let id = sourceId(for: moment)
        if id == "me" { return Color.coral }
        let index = abs(id.hashValue) % Self.sourceTints.count
        return Self.sourceTints[index]
    }

    private static let sourceTints: [Color] = [
        Color(hex: "#3E8E5A"), Color(hex: "#4A7BC8"),
        Color(hex: "#B8763E"), Color(hex: "#8C5BB8"),
    ]

    private func tint(forSource id: String) -> Color {
        if id == "me" { return Color.coral }
        return Self.sourceTints[abs(id.hashValue) % Self.sourceTints.count]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            sourceChips
            monthHeader
            weekdayHeader
            monthGrid
            dayDetail
        }
        .padding(.vertical, 4)
        // Moments load async and are often months out (a birthday 121 days
        // away isn't in this month's grid) — open on the first month that
        // actually has something so the calendar never looks empty.
        .onChange(of: moments.count) { _, _ in jumpToFirstMonthWithMoments() }
        .onAppear { jumpToFirstMonthWithMoments() }
    }

    @State private var didAutoJump = false

    private func jumpToFirstMonthWithMoments() {
        guard !didAutoJump, !moments.isEmpty else { return }
        let today = calendar.startOfDay(for: Date())
        let upcoming = moments.filter { $0.date >= today }.sorted { $0.date < $1.date }
        guard let first = upcoming.first else { return }
        didAutoJump = true
        // Already something this month? Stay put.
        guard !calendar.isDate(first.date, equalTo: visibleMonth, toGranularity: .month) else { return }
        let hasThisMonth = upcoming.contains {
            calendar.isDate($0.date, equalTo: visibleMonth, toGranularity: .month)
        }
        if !hasThisMonth {
            withAnimation(.snappy) { visibleMonth = first.date }
        }
    }

    // ── Calendar sources (the Google-Calendar left rail, as chips) ─────────

    private var sourceChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(sources) { source in
                    let isOn = !hiddenSources.contains(source.id)
                    Button {
                        withAnimation(.snappy) {
                            if isOn { hiddenSources.insert(source.id) }
                            else { hiddenSources.remove(source.id) }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(isOn ? tint(forSource: source.id) : Color.inkTertiary)
                                .frame(width: 8, height: 8)
                            Text(source.emoji.map { "\($0) \(source.name)" } ?? source.name)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(isOn ? Color.ink : Color.inkTertiary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(isOn ? Color.surface : Color.clear, in: Capsule())
                        .overlay(
                            Capsule().stroke(isOn ? Color.clear : Color.line, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(source.name) calendar")
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
            .padding(.horizontal, 20)
        }
        .sensoryFeedback(.selection, trigger: hiddenSources)
    }

    // ── Month navigation ──────────────────────────────────────────────────

    private var monthHeader: some View {
        HStack {
            Button {
                shiftMonth(-1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous month")

            Spacer()
            Text(monthTitle)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Color.ink)
                .contentTransition(.numericText())
            Spacer()

            Button {
                shiftMonth(1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next month")
        }
        .foregroundStyle(Color.ink)
        .padding(.horizontal, 12)
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: visibleMonth)
    }

    private func shiftMonth(_ delta: Int) {
        guard let next = calendar.date(byAdding: .month, value: delta, to: visibleMonth) else { return }
        withAnimation(.snappy) {
            visibleMonth = next
            selectedDay = nil
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(Array(calendar.veryShortWeekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.inkTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 14)
    }

    // ── The grid ──────────────────────────────────────────────────────────

    private var monthDays: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: visibleMonth) else { return [] }
        let first = interval.start
        let leading = calendar.component(.weekday, from: first) - calendar.firstWeekday
        let offset = (leading + 7) % 7
        let count = calendar.range(of: .day, in: .month, for: first)?.count ?? 30
        var cells: [Date?] = Array(repeating: nil, count: offset)
        for day in 0..<count {
            cells.append(calendar.date(byAdding: .day, value: day, to: first))
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }

    private func moments(on day: Date) -> [TimelineMoment] {
        shownMoments.filter { calendar.isDate($0.date, inSameDayAs: day) }
    }

    private var monthGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 4) {
            ForEach(Array(monthDays.enumerated()), id: \.offset) { _, day in
                if let day {
                    dayCell(day)
                } else {
                    Color.clear.frame(height: 46)
                }
            }
        }
        .padding(.horizontal, 12)
    }

    private func dayCell(_ day: Date) -> some View {
        let items = moments(on: day)
        let isToday = calendar.isDateInToday(day)
        let isSelected = selectedDay.map { calendar.isDate($0, inSameDayAs: day) } ?? false

        return Button {
            withAnimation(.snappy) {
                selectedDay = isSelected ? nil : day
            }
        } label: {
            VStack(spacing: 3) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.system(size: 14, weight: isToday ? .bold : .regular))
                    .foregroundStyle(
                        isSelected ? Color.white : (isToday ? Color.coral : Color.ink)
                    )
                    .frame(width: 28, height: 28)
                    .background(
                        Circle().fill(isSelected ? Color.coral : Color.clear)
                    )
                HStack(spacing: 3) {
                    ForEach(Array(items.prefix(3).enumerated()), id: \.offset) { _, item in
                        Circle()
                            .fill(tint(for: item))
                            .frame(width: 5, height: 5)
                    }
                }
                .frame(height: 5)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(dayAccessibilityLabel(day, count: items.count))
    }

    private func dayAccessibilityLabel(_ day: Date, count: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        let base = formatter.string(from: day)
        return count == 0 ? base : "\(base), \(count) moment\(count == 1 ? "" : "s")"
    }

    // ── Selected day / next-up list ───────────────────────────────────────

    @ViewBuilder
    private var dayDetail: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let day = selectedDay {
                let items = moments(on: day)
                Text(longDate(day))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.inkSecondary)
                    .padding(.horizontal, 20)

                if items.isEmpty {
                    Button(action: onAddDate) {
                        Label("Nothing yet — add a date", systemImage: "plus.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.coral)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(Color.surface)
                            .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.lg, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                } else {
                    momentRows(items)
                }
            } else {
                // Nothing picked — show what's next so the screen always leads
                // with an action.
                let upcoming = shownMoments
                    .filter { $0.date >= calendar.startOfDay(for: Date()) }
                    .sorted { $0.date < $1.date }
                    .prefix(3)
                if !upcoming.isEmpty {
                    Text("NEXT UP")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.inkTertiary)
                        .tracking(0.5)
                        .padding(.horizontal, 20)
                    momentRows(Array(upcoming))
                }
            }
        }
    }

    private func momentRows(_ items: [TimelineMoment]) -> some View {
        VStack(spacing: 8) {
            ForEach(items) { item in
                Button {
                    onSelectMoment(item)
                } label: {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(tint(for: item))
                            .frame(width: 3, height: 34)
                        Image(systemName: item.emoji)
                            .font(.system(size: 17))
                            .foregroundStyle(tint(for: item))
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color.ink)
                                .lineLimit(1)
                            Text(item.sourceLabel)
                                .font(.caption)
                                .foregroundStyle(Color.inkSecondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Text(item.days == 0 ? "Today" : "\(item.days)d")
                            .font(.system(size: 12, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(item.days <= 3 ? Color.coral : Color.inkSecondary)
                    }
                    .padding(12)
                    .background(Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.lg, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
    }

    private func longDate(_ day: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: day).uppercased()
    }
}
