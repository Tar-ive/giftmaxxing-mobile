import SwiftUI

// "Birthday freebies" — the Shop section for the TikTok/Reddit-famous free
// birthday stuff (Sephora gift, Starbucks drink, Denny's Grand Slam...).
// Horizontal teaser cards here; "See all" opens the full grouped catalog.
// During the user's birthday month the header flips into celebration mode.
struct BirthdayPerksSection: View {
    @ObservedObject private var store = BirthdayPerksStore.shared
    @State private var showAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.isBirthdayMonth ? "It's your birthday month! 🎂" : "Birthday freebies 🎂")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(store.isBirthdayMonth ? Color.coral : Color.ink)
                    Text(store.isBirthdayMonth
                         ? "These \(store.perks.count) freebies are live for you right now"
                         : "Free stuff brands give out every birthday — everybody loves a good deal")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    showAll = true
                } label: {
                    Text("See all \(store.perks.count)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.coral)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)

            // Teaser cards
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(store.perks.prefix(8)) { perk in
                        BirthdayPerkCard(perk: perk)
                            .onTapGesture { showAll = true }
                    }
                }
                .padding(.horizontal, 16)
            }

            // Reminder hook — capture birthday once; hero copy after.
            if !store.hasBirthday {
                Button {
                    showAll = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "bell.badge")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Add your birthday — get pinged when your freebies unlock")
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(Color.coral)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.coral.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
            }
        }
        .task { await store.load() }
        .sheet(isPresented: $showAll) {
            BirthdayPerksSheet()
        }
    }
}

// Compact teaser: brand chip + the free thing.
struct BirthdayPerkCard: View {
    let perk: BirthdayPerk

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color(hex: perk.color).opacity(0.15))
                        .frame(width: 34, height: 34)
                    Text(perk.emoji)
                        .font(.system(size: 16))
                }
                Text(perk.brand)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
            }
            Text(perk.gift)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
            Text(perk.window)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color(hex: perk.color))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color(hex: perk.color).opacity(0.12))
                .clipShape(Capsule())
        }
        .padding(12)
        .frame(width: 190, alignment: .leading)
        .background(Color.cream)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// Full catalog: birthday capture up top, then perks grouped by category.
struct BirthdayPerksSheet: View {
    @ObservedObject private var store = BirthdayPerksStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var browserTarget: BrowserTarget?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    BirthdayCaptureCard()

                    ForEach(store.categories, id: \.self) { category in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(category)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Color.ink)
                                .padding(.horizontal, 16)

                            VStack(spacing: 8) {
                                ForEach(store.perks(in: category)) { perk in
                                    BirthdayPerkRow(perk: perk) {
                                        if let url = URL(string: perk.url) {
                                            browserTarget = BrowserTarget(url: url)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }

                    Text("Perks are set by each brand's rewards program and can change — check the linked page for current terms.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }
                .padding(.top, 12)
            }
            .background(Color.surface)
            .navigationTitle("Birthday freebies")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $browserTarget) { target in
                SafariView(url: target.url)
                    .ignoresSafeArea()
            }
        }
    }
}

// One perk, full detail: what you get, how to claim, when — tap for the
// brand's signup/terms page.
struct BirthdayPerkRow: View {
    let perk: BirthdayPerk
    var onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color(hex: perk.color).opacity(0.15))
                        .frame(width: 44, height: 44)
                    Text(perk.emoji)
                        .font(.system(size: 20))
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(perk.brand)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.ink)
                        Spacer()
                        Text(perk.window)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color(hex: perk.color))
                    }
                    Text(perk.gift)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.ink)
                        .multilineTextAlignment(.leading)
                    Text(perk.how)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .padding(12)
            .background(Color.cream)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

// Month/day picker (no year — all we need for reminders). Saving schedules
// the yearly-repeating local notifications via BirthdayPerksStore.
struct BirthdayCaptureCard: View {
    @ObservedObject private var store = BirthdayPerksStore.shared
    @State private var isEditing = false
    @State private var month: Int = 1
    @State private var day: Int = 1

    private static let monthNames = Calendar.current.monthSymbols

    private var daysInSelectedMonth: Int {
        // Fixed non-leap reference year: Feb 29 birthdays celebrate Mar 1 rules
        // anyway, and 29 in the wheel would over-promise the notification date.
        let comps = DateComponents(year: 2025, month: month)
        guard let date = Calendar.current.date(from: comps),
              let range = Calendar.current.range(of: .day, in: .month, for: date) else { return 31 }
        return range.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let monthName = store.birthMonthName, !isEditing {
                HStack {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.coral)
                    Text(store.isBirthdayMonth
                         ? "Your freebies are live all \(monthName)!"
                         : "We'll ping you when \(monthName) arrives")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.ink)
                    Spacer()
                    Button("Change") {
                        month = store.birthMonth ?? 1
                        day = store.birthDay ?? 1
                        isEditing = true
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.coral)
                }
            } else {
                Text(isEditing ? "Update your birthday" : "When's your birthday?")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.ink)
                Text("Month and day only — we'll remind you the moment your freebies unlock.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                HStack(spacing: 0) {
                    Picker("Month", selection: $month) {
                        ForEach(1...12, id: \.self) { m in
                            Text(Self.monthNames[m - 1]).tag(m)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                    .clipped()

                    Picker("Day", selection: $day) {
                        ForEach(1...daysInSelectedMonth, id: \.self) { d in
                            Text("\(d)").tag(d)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                    .clipped()
                }
                .frame(height: 110)
                .onChange(of: month) { _, _ in
                    if day > daysInSelectedMonth { day = daysInSelectedMonth }
                }

                Button {
                    store.birthMonth = month
                    store.birthDay = min(day, daysInSelectedMonth)
                    isEditing = false
                } label: {
                    Text("Save & remind me")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.coral)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Color.coral.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }
}
