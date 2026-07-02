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

        do {
            let fetched = try await api.fetchUpcomingEvents(userId: userId)
            let mapped = fetched.map { event -> GiftEvent in
                GiftEvent(
                    id: event.eventId ?? UUID().uuidString,
                    userId: userId,
                    type: event.type ?? "other",
                    title: event.title ?? event.type ?? "Event",
                    date: Date(timeIntervalSince1970: (event.date ?? 0) / 1000),
                    recipientName: event.recipientName ?? "",
                    scope: event.scope
                )
            }
            events = mapped

            if let context {
                cacheEvents(mapped, userId: userId, context: context)
            }
        } catch {
            // keep cached data
        }

        isLoading = false
    }

    func addEvent(_ event: GiftEvent, context: ModelContext?) {
        events.append(event)

        if let context {
            let cached = CachedEvent(from: event, userId: AuthManager.shared.userId ?? "", synced: false)
            context.insert(cached)
            try? context.save()

            OfflineQueue.shared.enqueue(
                context: context,
                method: "POST",
                path: "/events",
                body: [
                    "userId": AuthManager.shared.userId ?? "",
                    "title": event.title,
                    "type": event.type,
                    "date": String(Int(event.date.timeIntervalSince1970 * 1000)),
                    "recipientName": event.recipientName,
                ]
            )
        }
    }

    private func loadFromCache(context: ModelContext) {
        let descriptor = FetchDescriptor<CachedEvent>(
            sortBy: [SortDescriptor(\.eventDate)]
        )
        if let cached = try? context.fetch(descriptor), !cached.isEmpty {
            events = cached.map { $0.toGiftEvent() }
        }
    }

    private func cacheEvents(_ events: [GiftEvent], userId: String, context: ModelContext) {
        try? context.delete(model: CachedEvent.self)
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

struct EventsView: View {
    @StateObject private var viewModel = EventsViewModel()
    @Environment(\.modelContext) private var modelContext

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
                        ForEach(viewModel.upcomingEvents) { event in
                            NavigationLink {
                                EventDetailView(event: event)
                            } label: {
                                EventCard(event: event)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(16)
            }
            .background(Color.surface)
            .navigationTitle("Events")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
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

                if !event.recipientName.isEmpty {
                    Text("For \(event.recipientName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                    Button(action: {
                        let event = GiftEvent(
                            id: UUID().uuidString,
                            type: type,
                            title: title.isEmpty ? type.capitalized : title,
                            date: date,
                            recipientName: recipientName
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
        }
    }
}
