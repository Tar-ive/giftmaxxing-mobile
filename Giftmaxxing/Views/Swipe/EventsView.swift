import SwiftUI
import SwiftData

@MainActor
final class EventsViewModel: ObservableObject {
    @Published var events: [GiftEvent] = []
    @Published var showAddEvent = false
    @Published var isLoading = false

    private let api = APIClient.shared

    var upcomingEvents: [GiftEvent] {
        events
            .filter { $0.daysUntil >= 0 }
            .sorted { $0.daysUntil < $1.daysUntil }
    }

    // Urgency buckets — "what needs a gift NOW" scans better than one long list.
    var sections: [(title: String, events: [GiftEvent])] {
        let upcoming = upcomingEvents
        let week = upcoming.filter { $0.daysUntil <= 7 }
        let month = upcoming.filter { $0.daysUntil > 7 && $0.daysUntil <= 31 }
        let later = upcoming.filter { $0.daysUntil > 31 }
        return [
            ("This week", week),
            ("This month", month),
            ("Later", later),
        ].filter { !$0.1.isEmpty }
    }

    func loadEvents(context: ModelContext?) async {
        if let context {
            loadFromCache(context: context)
        }

        guard let userId = AuthManager.shared.userId else {
            // Signed-out demo parity with the web app: show the same social
            // circle's upcoming occasions so the screen is never dead.
            if events.isEmpty { events = Self.demoEvents() }
            return
        }
        isLoading = true

        // Two server stores hold dates: /events/upcoming (occasions logged on
        // the profile during onboarding) and /events (the unified table where
        // user-added dates live). Merge both, dedupe by id.
        async let upcomingTask = try? api.fetchUpcomingEvents(userId: userId)
        async let unifiedTask = try? api.fetchEvents(userId: userId, scope: "personal")
        let (upcoming, unified) = await (upcomingTask, unifiedTask)

        if upcoming != nil || unified != nil {
            var seen = Set<String>()
            var mapped: [GiftEvent] = []
            for event in (upcoming ?? []) + (unified ?? []) {
                guard let date = event.date?.dateValue else { continue }
                let id = event.eventId ?? UUID().uuidString
                guard !seen.contains(id) else { continue }
                seen.insert(id)
                mapped.append(GiftEvent(
                    id: id,
                    userId: userId,
                    type: event.type ?? "other",
                    title: event.title ?? event.recipientName.map { "\($0)'s \(event.type ?? "day")" } ?? event.type ?? "Event",
                    date: date,
                    recipientName: event.recipientName ?? event.recipient?.name ?? "",
                    reminderLeadDays: event.reminderLeadDays,
                    budget: event.budget,
                    scope: event.scope
                ))
            }
            events = mapped

            if let context {
                cacheEvents(mapped, userId: userId, context: context)
            }
            // Deletions made elsewhere drop their notifications here too.
            ReminderScheduler.resync(events: mapped)
        }

        isLoading = false
    }

    func addEvent(_ event: GiftEvent, context: ModelContext?) {
        events.append(event)

        // The reminder is local-first: scheduled the moment the event exists,
        // no server round-trip needed.
        ReminderScheduler.schedule(for: event)

        guard let context else { return }

        // Scope the cache to WHOEVER owns this event. Signed in → their userId;
        // signed out → this DEVICE's anon id (never the empty string, which is a
        // shared global key — imported contacts under "" leaked to every user).
        let signedInId = AuthManager.shared.userId
        let scopeId = signedInId ?? InteractionQueue.anonymousUserId
        let cached = CachedEvent(from: event, userId: scopeId, synced: signedInId == nil)
        context.insert(cached)
        try? context.save()

        // Only sync to the server when we have a REAL account. Imported
        // contacts/birthdays are PII — never POST them under an empty userId.
        guard let userId = signedInId, !userId.isEmpty else { return }

        // POST /events expects { userId, event: {…} } with a YYYY-MM-DD date
        // (a flat epoch-millis body silently stored an empty event).
        var eventBody: [String: Any] = [
            "eventId": event.id,
            "title": event.title,
            "type": event.type,
            "date": FlexibleDate.ymdString(from: event.date),
            "recipientName": event.recipientName,
            "scope": "personal",
        ]
        if let lead = event.reminderLeadDays { eventBody["reminderLeadDays"] = lead }
        if let budget = event.budget { eventBody["budget"] = budget }
        if let notes = event.notes, !notes.isEmpty { eventBody["notes"] = notes }

        OfflineQueue.shared.enqueue(
            context: context,
            method: "POST",
            path: "/events",
            body: ["userId": userId, "event": eventBody]
        )
    }

    func deleteEvent(_ event: GiftEvent, context: ModelContext?) {
        events.removeAll { $0.id == event.id }
        ReminderScheduler.cancel(eventId: event.id)

        if let context {
            let id = event.id
            let descriptor = FetchDescriptor<CachedEvent>(predicate: #Predicate { $0.eventId == id })
            if let cached = try? context.fetch(descriptor) {
                cached.forEach { context.delete($0) }
                try? context.save()
            }

            // Demo rows only exist client-side; real ones sync the delete.
            if let userId = AuthManager.shared.userId, !event.id.hasPrefix("demo_") {
                OfflineQueue.shared.enqueue(
                    context: context,
                    method: "POST",
                    path: "/events/delete",
                    body: ["userId": userId, "eventId": event.id]
                )
            }
        }
    }

    private func loadFromCache(context: ModelContext) {
        // Only ever show the CURRENT account's (or this guest device's) events —
        // never another account's cached rows sitting in the shared SwiftData
        // store on this device.
        let scope = AuthManager.shared.userId ?? InteractionQueue.anonymousUserId
        let descriptor = FetchDescriptor<CachedEvent>(
            predicate: #Predicate { $0.userId == scope },
            sortBy: [SortDescriptor(\.eventDate)]
        )
        if let cached = try? context.fetch(descriptor), !cached.isEmpty {
            events = cached.map { $0.toGiftEvent() }
        }
    }

    private func cacheEvents(_ events: [GiftEvent], userId: String, context: ModelContext) {
        // Replace only THIS account's cached rows (don't nuke another account's).
        let existing = FetchDescriptor<CachedEvent>(predicate: #Predicate { $0.userId == userId })
        if let rows = try? context.fetch(existing) {
            rows.forEach { context.delete($0) }
        }
        for event in events {
            let cached = CachedEvent(from: event, userId: userId)
            context.insert(cached)
        }
        try? context.save()
    }

    // Mirrors the demo social circle used across the web app (Maya's birthday
    // in 4 days, Noor in 11, Ivy's anniversary in 18, Remy's housewarming).
    static func demoEvents() -> [GiftEvent] {
        func inDays(_ days: Int) -> Date {
            Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
        }
        return [
            GiftEvent(id: "demo_maya", type: "birthday", title: "Maya's Birthday", date: inDays(4), recipientName: "Maya Reyes", budget: 90),
            GiftEvent(id: "demo_sam", type: "other", title: "Sam's Farewell", date: inDays(7), recipientName: "Sam Okafor", notes: "Off to Lisbon \u{1F6EB}"),
            GiftEvent(id: "demo_noor", type: "birthday", title: "Noor's Birthday", date: inDays(11), recipientName: "Noor Haddad", budget: 50),
            GiftEvent(id: "demo_ivy", type: "anniversary", title: "Ivy & Alex's Anniversary", date: inDays(18), recipientName: "Ivy Castellano"),
            GiftEvent(id: "demo_remy", type: "housewarming", title: "Remy's Housewarming", date: inDays(25), recipientName: "Remy Adebayo"),
        ]
    }
}

// The personal gift calendar — birthdays, anniversaries, occasions, and the
// reminders that pace them. Reached from You → Settings → Gift calendar
// (it used to live on the Circles tab, which is now invite-only).
struct EventsView: View {
    @StateObject private var viewModel = EventsViewModel()
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    if viewModel.isLoading && viewModel.events.isEmpty {
                        ProgressView()
                            .padding(40)
                    } else if viewModel.upcomingEvents.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "calendar.badge.plus")
                                .font(.system(size: 40))
                                .foregroundStyle(.secondary)
                            Text("No upcoming events")
                                .font(.displaySmall)
                                .foregroundStyle(Color.ink)
                            Text("Add birthdays, anniversaries, and occasions to never miss a gift")
                                .font(.bodyMedium)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)

                            Button(action: { viewModel.showAddEvent = true }) {
                                Text("Add event")
                                    .font(.labelBold)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 12)
                                    .background(Color.coral)
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(40)
                    } else {
                        ForEach(viewModel.sections, id: \.title) { section in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(section.title)
                                    .font(.system(size: 13, weight: .heavy))
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)
                                    .padding(.leading, 4)

                                ForEach(section.events) { event in
                                    NavigationLink {
                                        EventDetailView(event: event)
                                    } label: {
                                        EventCard(event: event)
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            viewModel.deleteEvent(event, context: modelContext)
                                        } label: {
                                            Label("Delete event", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(Color.surface)
            .navigationTitle("Gift calendar")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { viewModel.showAddEvent = true }) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.coral)
                    }
                }
            }
            .sheet(isPresented: $viewModel.showAddEvent) {
                AddEventSheet { event in
                    viewModel.addEvent(event, context: modelContext)
                }
            }
        }
        .task {
            if viewModel.events.isEmpty {
                await viewModel.loadEvents(context: modelContext)
            }
        }
    }
}

struct EventCard: View {
    let event: GiftEvent

    var urgencyColor: Color {
        let days = event.daysUntil
        if days <= 3 { return .red }
        if days <= 7 { return .orange }
        if days <= 14 { return Color.coral }
        return .secondary
    }

    var body: some View {
        HStack(spacing: 14) {
            Text(event.eventTypeIcon)
                .font(.system(size: 28))
                .frame(width: 52, height: 52)
                .background(Color.cream)
                .clipShape(RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.ink)

                Text(event.dateString)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    if !event.recipientName.isEmpty {
                        Text("For \(event.recipientName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let budget = event.budget {
                        Text("$\(Int(budget)) budget")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.coral)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.coralSoft)
                            .clipShape(Capsule())
                    }
                }
            }

            Spacer()

            VStack(spacing: 2) {
                Text("\(event.daysUntil)")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(urgencyColor)
                Text(event.daysUntil == 1 ? "day" : "days")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }
}

struct AddEventSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var type = "birthday"
    @State private var date = Date()
    @State private var recipientName = ""
    @State private var remind = true
    @State private var reminderLeadDays = ReminderScheduler.defaultLeadDays
    @State private var budgetText = ""
    var onAdd: ((GiftEvent) -> Void)?

    private let eventTypes = ["birthday", "anniversary", "holiday", "graduation", "wedding", "housewarming", "baby_shower", "other"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Event details") {
                    TextField("Event title", text: $title)
                    TextField("For whom?", text: $recipientName)
                    Picker("Type", selection: $type) {
                        ForEach(eventTypes, id: \.self) { t in
                            Text(t.replacingOccurrences(of: "_", with: " ").capitalized)
                                .tag(t)
                        }
                    }
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }

                Section {
                    Toggle("Remind me", isOn: $remind)
                    if remind {
                        Picker("When", selection: $reminderLeadDays) {
                            ForEach(ReminderScheduler.leadChoices, id: \.days) { choice in
                                Text(choice.label).tag(choice.days)
                            }
                        }
                    }
                } header: {
                    Text("Reminder")
                } footer: {
                    Text(remind
                         ? "A nudge lands on your phone with enough runway to actually get the gift — plus one on the day."
                         : "No reminder — the date just lives in your list.")
                }

                Section("Budget (optional)") {
                    TextField("e.g. 50", text: $budgetText)
                        .keyboardType(.numberPad)
                }

                Section {
                    Button(action: {
                        let event = GiftEvent(
                            id: UUID().uuidString,
                            type: type,
                            title: title.isEmpty ? type.capitalized : title,
                            date: date,
                            recipientName: recipientName,
                            reminderLeadDays: remind ? reminderLeadDays : nil,
                            budget: Double(budgetText.trimmingCharacters(in: .whitespaces))
                        )
                        onAdd?(event)
                        dismiss()
                    }) {
                        Text("Add Event")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.coral)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("New Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                await ReminderScheduler.requestPermissionIfNeeded()
            }
        }
    }
}
