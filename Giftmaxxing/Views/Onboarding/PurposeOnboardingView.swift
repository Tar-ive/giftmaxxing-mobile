import SwiftUI
import Contacts

// Purpose-driven onboarding — six steps that end in a HABIT, not a sign-up:
//   1. "What brings you here?"      — pick a persona
//   2. Import contacts (optional)   — birthdays become calendar events
//   3. Quick preferences            — relationships, budget, gift style
//   4. First micro-action           — "[Name]'s birthday is in 2 weeks…"
//   5. Sample curation              — save one real idea + write a why-note
//   6. Dashboard tour               — CoachMarksView, queued by ContentView
// Steps 1/3 seed the feed's vibes immediately; steps 2/4/5 create real
// events, a real Gift Board, and the first Thoughtfulness Points.

// The choices steps 1 + 3 collect, persisted for the feed and future flows.
enum GiftingPrefs {
    private static let personaKey = "onboarding.persona"
    private static let relationshipsKey = "onboarding.relationships"
    private static let budgetKey = "onboarding.budget"
    private static let stylesKey = "onboarding.giftStyles"

    static var persona: String? {
        get { UserDefaults.standard.string(forKey: personaKey) }
        set { UserDefaults.standard.set(newValue, forKey: personaKey) }
    }
    static var relationships: [String] {
        get { UserDefaults.standard.stringArray(forKey: relationshipsKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: relationshipsKey) }
    }
    static var budget: String? {
        get { UserDefaults.standard.string(forKey: budgetKey) }
        set { UserDefaults.standard.set(newValue, forKey: budgetKey) }
    }
    static var giftStyles: [String] {
        get { UserDefaults.standard.stringArray(forKey: stylesKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: stylesKey) }
    }

    // Account deletion — forget the onboarding answers.
    static func clear() {
        for k in [personaKey, relationshipsKey, budgetKey, stylesKey] {
            UserDefaults.standard.removeObject(forKey: k)
        }
    }
}

struct PurposeOnboardingView: View {
    var onDone: () -> Void

    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.modelContext) private var modelContext
    @StateObject private var eventsModel = EventsViewModel()

    @State private var step = 0
    private let stepCount = 5

    // Step 1
    @State private var persona: String?
    // Step 2
    @State private var contacts: [ImportableContact] = []
    @State private var selectedContacts = Set<String>()
    @State private var contactsDenied = false
    @State private var contactsLoaded = false
    @State private var importedEvents: [GiftEvent] = []
    // Step 3
    @State private var relationships = Set<String>()
    @State private var budget: String?
    @State private var styles = Set<String>()
    // Step 5
    @State private var samplePicks: [Post] = []
    @State private var savedPick: Post?
    @State private var picksFailed = false
    @State private var note = ""

    struct ImportableContact: Identifiable {
        let id: String
        let name: String
        let nextBirthday: Date
        var daysUntil: Int {
            Calendar.current.dateComponents(
                [.day],
                from: Calendar.current.startOfDay(for: Date()),
                to: Calendar.current.startOfDay(for: nextBirthday)
            ).day ?? 0
        }
    }

    private static let personas: [(id: String, icon: String, label: String)] = [
        ("thoughtful", "heart.text.square.fill", "I always want to give more thoughtful gifts"),
        ("fast", "bolt.fill", "I need gift ideas fast"),
        ("special", "sparkles", "I love making others feel special"),
    ]
    private static let relationshipOptions = ["Partner", "Parent", "Best friend", "Sibling", "Grandparent", "Coworker", "My kids"]
    private static let budgetOptions = ["Under $25", "$25–75", "$75–200", "$200+"]
    private static let styleOptions: [(id: String, label: String)] = [
        ("handmade", "Handmade"), ("experiences", "Experiences"), ("personalized", "Personalized"),
    ]

    // The step-4 hook: the soonest imported birthday, if any.
    private var nextOccasion: ImportableContact? {
        contacts
            .filter { selectedContacts.contains($0.id) }
            .min(by: { $0.daysUntil < $1.daysUntil })
    }

    var body: some View {
        VStack(spacing: 0) {
            // Progress dots
            HStack(spacing: 6) {
                ForEach(0..<stepCount, id: \.self) { i in
                    Capsule()
                        .fill(i == step ? Color.coral : Color.line)
                        .frame(width: i == step ? 20 : 6, height: 6)
                }
                Spacer()
                if step > 0 && step < 4 {
                    Button("Skip") { advance() }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .animation(.spring(response: 0.3), value: step)
            .padding(.horizontal, 24)
            .padding(.top, 16)

            ScrollView {
                Group {
                    switch step {
                    case 0: personaStep
                    case 1: contactsStep
                    case 2: preferencesStep
                    case 3: microActionStep
                    default: curationStep
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 32)
            }

            footer
        }
        .background(Color.surface)
    }

    // ── Step 1: persona ───────────────────────────────────────────────────

    private var personaStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepTitle("What brings you here?", subtitle: "This shapes what Giftmaxxing shows you first.")
            ForEach(Self.personas, id: \.id) { option in
                Button {
                    persona = option.id
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: option.icon)
                            .font(.system(size: 20))
                            .foregroundStyle(persona == option.id ? .white : Color.coral)
                            .frame(width: 44, height: 44)
                            .background(persona == option.id ? Color.coral : Color.coralSoft)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        Text(option.label)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.ink)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        if persona == option.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.coral)
                        }
                    }
                    .padding(14)
                    .background(Color.cream)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(persona == option.id ? Color.coral : .clear, lineWidth: 1.5)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // ── Step 2: contacts import (optional) ────────────────────────────────

    private var contactsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepTitle(
                "Never miss their day",
                subtitle: "Import birthdays from your contacts — optional, stays on your device."
            )

            if !contactsLoaded && !contactsDenied {
                Button {
                    Task { await loadContacts() }
                } label: {
                    HStack {
                        Spacer()
                        Image(systemName: "person.crop.circle.badge.plus")
                        Text("Find birthdays in my contacts").font(.labelBold)
                        Spacer()
                    }
                    .padding(.vertical, 15)
                    .background(Color.coral)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                }
            } else if contactsDenied {
                Text("No problem — you can add dates any time in Circles.")
                    .font(.bodyMedium)
                    .foregroundStyle(.secondary)
            } else if contacts.isEmpty {
                Text("No contacts with birthdays found — you can add dates any time in Circles.")
                    .font(.bodyMedium)
                    .foregroundStyle(.secondary)
            }

            ForEach(contacts) { contact in
                Button {
                    if selectedContacts.contains(contact.id) {
                        selectedContacts.remove(contact.id)
                    } else {
                        selectedContacts.insert(contact.id)
                    }
                } label: {
                    HStack(spacing: 12) {
                        AvatarView(name: contact.name, grad: .sky, size: 40)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(contact.name)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.ink)
                            Text("🎂 in \(contact.daysUntil) day\(contact.daysUntil == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: selectedContacts.contains(contact.id) ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 22))
                            .foregroundStyle(selectedContacts.contains(contact.id) ? Color.coral : Color.line)
                    }
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // ── Step 3: quick preferences ─────────────────────────────────────────

    private var preferencesStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            stepTitle("Who do you gift for most?", subtitle: "Pick up to 4 — plus your usual budget and style.")

            chipGrid(Self.relationshipOptions, selection: $relationships, max: 4)

            Text("TYPICAL BUDGET")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(Self.budgetOptions, id: \.self) { option in
                    Button {
                        budget = option
                    } label: {
                        Text(option)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(budget == option ? .white : Color.ink)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 9)
                            .frame(maxWidth: .infinity)
                            .background(budget == option ? Color.ink : Color.cream)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("YOU LEAN TOWARD")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(Self.styleOptions, id: \.id) { option in
                    Button {
                        if styles.contains(option.id) { styles.remove(option.id) } else { styles.insert(option.id) }
                    } label: {
                        Text(option.label)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(styles.contains(option.id) ? .white : Color.coral)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(styles.contains(option.id) ? Color.coral : Color.coralSoft)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
        }
    }

    // ── Step 4: first micro-action ────────────────────────────────────────

    private var microActionStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let occasion = nextOccasion {
                stepTitle("Great — let's put this to work", subtitle: nil)
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "birthday.cake.fill").foregroundStyle(Color.coral)
                        .font(.system(size: 40))
                    Text("\(occasion.name) has a birthday in \(occasion.daysUntil) days.")
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.ink)
                    Text("Save one idea now and their Gift Board is started.")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.coralSoft.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 18))
            } else {
                // No imported birthday to anchor on — this step used to render
                // a bare heading (a blank screen). Show what the app actually
                // does for them instead: dates, friends' profiles, taste.
                stepTitle("Here's how gifting gets easy", subtitle: nil)
                VStack(spacing: 10) {
                    ForEach(Self.valueProps, id: \.title) { prop in
                        valuePropRow(prop)
                    }
                }
            }
        }
    }

    private struct ValueProp {
        let icon: String
        let title: String
        let line: String
    }

    // The real product story — log the dates, connect the people, let their
    // profile answer the awkward questions, and the taste model does the rest.
    private static let valueProps: [ValueProp] = [
        ValueProp(
            icon: "calendar",
            title: "Log the dates that matter",
            line: "Birthdays, graduations, anniversaries — we remind you in time to actually shop."
        ),
        ValueProp(
            icon: "person.2.fill",
            title: "Connect your people",
            line: "Friends on Giftmaxxing keep a profile you can gift from."
        ),
        ValueProp(
            icon: "ruler.fill",
            title: "No more awkward questions",
            line: "Their sizes and what to avoid live on their profile — the surprise stays a surprise."
        ),
        ValueProp(
            icon: "sparkles",
            title: "Ideas that fit them",
            line: "A few swipes from them and we rank what they'd actually love."
        ),
    ]

    private func valuePropRow(_ prop: ValueProp) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: prop.icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.coral)
                .frame(width: 44, height: 44)
                .background(Color.coralSoft)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(prop.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.ink)
                Text(prop.line)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // ── Step 5: sample curation ───────────────────────────────────────────

    private var curationStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepTitle(
                savedPick == nil ? "Pick one that feels right" : "Why does it fit?",
                subtitle: savedPick == nil
                    ? (nextOccasion.map { "Thinking of \($0.name) —" } ?? "") + " tap the one you'd actually consider."
                    : "One line is plenty."
            )

            if samplePicks.isEmpty {
                if picksFailed {
                    // Offline / empty feed used to leave a spinner forever with
                    // no way forward (no Skip on this step) — give them both a
                    // retry and an exit.
                    VStack(spacing: 12) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                        Text("Couldn't load ideas right now")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.ink)
                        Text("You can do this any time from Home.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        Button("Try again") {
                            Task { await loadSamplePicks() }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(24)
                } else {
                    ProgressView("Finding ideas…")
                        .font(.bodyMedium)
                        .frame(maxWidth: .infinity)
                        .padding(30)
                        .task { await loadSamplePicks() }
                }
            } else if let saved = savedPick {
                // The saved idea + the why-note (the habit lock-in).
                HStack(spacing: 12) {
                    ZStack {
                        Color.gradient(for: saved.product.grad)
                        if let image = saved.product.image {
                            CachedAsyncImage(url: image, width: 300)
                        }
                    }
                    .frame(width: 72, height: 72)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(saved.product.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.ink)
                            .lineLimit(2)
                        Label("Saved to \(nextOccasion.map { "\($0.name)'s board" } ?? "your first Gift Board")", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.coral)
                    }
                    Spacer()
                }
                .padding(12)
                .background(Color.cream)
                .clipShape(RoundedRectangle(cornerRadius: 16))

                TextField("e.g. She's been talking about this for months…", text: $note, axis: .vertical)
                    .lineLimit(2...4)
                    .padding(12)
                    .background(Color.cream)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 12) {
                    ForEach(samplePicks) { post in
                        Button {
                            savePick(post)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                ZStack {
                                    Color.gradient(for: post.product.grad)
                                    if let image = post.product.image {
                                        CachedAsyncImage(url: image, width: 400)
                                    }
                                }
                                .aspectRatio(1, contentMode: .fit)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                Text(post.product.name)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.ink)
                                    .lineLimit(1)
                                if post.product.price > 0 {
                                    Text("$\(Int(post.product.price))")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(Color.coral)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // ── Chrome ────────────────────────────────────────────────────────────

    private func stepTitle(_ title: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.ink)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        Button {
            advance()
        } label: {
            Text(footerLabel)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(footerEnabled ? Color.coral : Color.coral.opacity(0.4))
                .clipShape(Capsule())
        }
        .disabled(!footerEnabled)
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(Color.surface)
    }

    private var footerLabel: String {
        switch step {
        case 1: return selectedContacts.isEmpty ? "Continue" : "Import \(selectedContacts.count) & continue"
        case 3: return nextOccasion == nil ? "Let's go" : "Show me ideas"
        case 4:
            if savedPick != nil { return "Finish — show me around" }
            return picksFailed ? "Show me around" : "Pick one to continue"
        default: return "Continue"
        }
    }

    private var footerEnabled: Bool {
        switch step {
        case 0: return persona != nil
        // Ideas that never loaded must not trap them on the last step.
        case 4: return savedPick != nil || picksFailed
        default: return true
        }
    }

    private func advance() {
        switch step {
        case 0:
            GiftingPrefs.persona = persona
            step = 1
        case 1:
            importSelectedContacts()
            step = 2
        case 2:
            GiftingPrefs.relationships = Array(relationships)
            GiftingPrefs.budget = budget
            GiftingPrefs.giftStyles = Array(styles)
            // Styles + persona seed the feed's vibes immediately — the very
            // first Home page already leans the right way.
            var vibes = Array(styles)
            if persona == "thoughtful" { vibes.append("thoughtful") }
            if !vibes.isEmpty { PersonalizationStore.consultVibes = vibes }
            step = 3
        case 3:
            step = 4
        default:
            if let saved = savedPick { finishCuration(saved) }
            onDone()
        }
    }

    private func chipGrid(_ options: [String], selection: Binding<Set<String>>, max: Int) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(options, id: \.self) { option in
                let isOn = selection.wrappedValue.contains(option)
                Button {
                    if isOn {
                        selection.wrappedValue.remove(option)
                    } else if selection.wrappedValue.count < max {
                        selection.wrappedValue.insert(option)
                    }
                } label: {
                    Text(option)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(isOn ? .white : Color.ink)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity)
                        .background(isOn ? Color.coral : Color.cream)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // ── Work ──────────────────────────────────────────────────────────────

    private func loadContacts() async {
        let store = CNContactStore()
        let granted = (try? await store.requestAccess(for: .contacts)) ?? false
        guard granted else {
            contactsDenied = true
            return
        }
        let found: [ImportableContact] = await Task.detached(priority: .userInitiated) {
            let keys = [
                CNContactGivenNameKey, CNContactFamilyNameKey, CNContactBirthdayKey,
            ] as [CNKeyDescriptor]
            let request = CNContactFetchRequest(keysToFetch: keys)
            var result: [ImportableContact] = []
            try? store.enumerateContacts(with: request) { contact, _ in
                guard let birthday = contact.birthday,
                      let month = birthday.month, let day = birthday.day else { return }
                let name = [contact.givenName, contact.familyName]
                    .filter { !$0.isEmpty }.joined(separator: " ")
                guard !name.isEmpty else { return }
                let calendar = Calendar.current
                var next = DateComponents(month: month, day: day)
                next.year = calendar.component(.year, from: Date())
                guard var date = calendar.date(from: next) else { return }
                if date < calendar.startOfDay(for: Date()) {
                    date = calendar.date(byAdding: .year, value: 1, to: date) ?? date
                }
                result.append(ImportableContact(id: contact.identifier, name: name, nextBirthday: date))
            }
            return result.sorted { $0.nextBirthday < $1.nextBirthday }
        }.value
        contacts = Array(found.prefix(30))
        contactsLoaded = true
        // Pre-select the soonest few — one tap keeps them all.
        selectedContacts = Set(contacts.prefix(5).map(\.id))
    }

    private func importSelectedContacts() {
        for contact in contacts where selectedContacts.contains(contact.id) {
            let event = GiftEvent(
                id: "evt_\(UUID().uuidString.prefix(8))",
                userId: authManager.userId,
                recipientId: nil,
                type: "birthday",
                title: "\(contact.name)'s birthday",
                date: contact.nextBirthday,
                recipientName: contact.name,
                recurrence: "yearly",
                reminderLeadDays: 14,
                budget: nil,
                notes: nil,
                scope: "personal",
                createdAt: Date()
            )
            eventsModel.addEvent(event, context: modelContext)
            importedEvents.append(event)
        }
    }

    private func loadSamplePicks() async {
        guard samplePicks.isEmpty else { return }
        picksFailed = false
        var page = try? await APIClient.shared.fetchFeed(
            limit: 24,
            vibes: PersonalizationStore.consultVibes.isEmpty ? nil : PersonalizationStore.consultVibes,
            cacheBuster: String(Int(Date().timeIntervalSince1970 * 1000))
        )
        // The vibe filter can legitimately return nothing — fall back to the
        // unfiltered feed before declaring failure.
        if (page?.posts ?? []).isEmpty, !PersonalizationStore.consultVibes.isEmpty {
            page = try? await APIClient.shared.fetchFeed(limit: 24)
        }
        samplePicks = (page?.posts ?? [])
            .filter { $0.product.image != nil && $0.feedEligible != false }
            .prefix(6)
            .map { $0 }
        picksFailed = samplePicks.isEmpty
    }

    private func savePick(_ post: Post) {
        let boardName = nextOccasion.map { "\($0.name)'s birthday" } ?? "My first Gift Board"
        let board = SwipeListStore.shared.createList(
            name: boardName,
            recipientName: nextOccasion?.name,
            occasion: nextOccasion != nil ? "birthday" : nil
        )
        SwipeListStore.shared.toggle(post, in: board.id)
        savedPick = post
    }

    private func finishCuration(_ post: Post) {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let board = SwipeListStore.shared.lists.first(where: { list in
                  list.posts.contains(where: { $0.id == post.id })
              }) else { return }
        SwipeListStore.shared.setNote(trimmed, for: post.id, in: board.id)
    }
}
