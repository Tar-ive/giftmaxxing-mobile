import SwiftUI

@MainActor
final class EventsViewModel: ObservableObject {
    @Published var events: [GiftEvent] = GiftEvent.samples
    @Published var showAddEvent = false

    var upcomingEvents: [GiftEvent] {
        events
            .filter { ($0.daysUntil ?? Int.max) >= 0 }
            .sorted { ($0.daysUntil ?? Int.max) < ($1.daysUntil ?? Int.max) }
    }

    var pastEvents: [GiftEvent] {
        events.filter { ($0.daysUntil ?? 0) < 0 }
    }
}

struct EventsView: View {
    @StateObject private var viewModel = EventsViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    if viewModel.upcomingEvents.isEmpty {
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
                            EventCard(event: event)
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
                AddEventSheet()
            }
        }
    }
}

struct EventCard: View {
    let event: GiftEvent

    var urgencyColor: Color {
        guard let days = event.daysUntil else { return .secondary }
        if days <= 3 { return .red }
        if days <= 7 { return .orange }
        if days <= 14 { return Color.coral }
        return .secondary
    }

    var body: some View {
        HStack(spacing: 14) {
            // Icon
            Text(event.eventTypeIcon)
                .font(.system(size: 28))
                .frame(width: 52, height: 52)
                .background(Color.cream)
                .clipShape(RoundedRectangle(cornerRadius: 14))

            // Info
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title ?? event.type.capitalized)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.ink)

                if let date = event.date {
                    Text(date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Countdown
            if let days = event.daysUntil {
                VStack(spacing: 2) {
                    Text("\(days)")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(urgencyColor)
                    Text(days == 1 ? "day" : "days")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
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
                    Button(action: { dismiss() }) {
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

extension GiftEvent {
    static let samples: [GiftEvent] = {
        let cal = Calendar.current
        let today = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        return [
            GiftEvent(
                id: "e1",
                userId: "you",
                recipientId: "maya",
                type: "birthday",
                title: "Maya's Birthday",
                date: formatter.string(from: cal.date(byAdding: .day, value: 4, to: today)!),
                recurrence: "yearly",
                reminderLeadDays: 7,
                budget: 50
            ),
            GiftEvent(
                id: "e2",
                userId: "you",
                recipientId: "noor",
                type: "birthday",
                title: "Noor's Birthday",
                date: formatter.string(from: cal.date(byAdding: .day, value: 11, to: today)!),
                recurrence: "yearly",
                reminderLeadDays: 7,
                budget: 30
            ),
            GiftEvent(
                id: "e3",
                userId: "you",
                recipientId: "ivy",
                type: "anniversary",
                title: "Ivy & Alex Anniversary",
                date: formatter.string(from: cal.date(byAdding: .day, value: 18, to: today)!),
                recurrence: "yearly",
                reminderLeadDays: 14,
                budget: 75
            ),
            GiftEvent(
                id: "e4",
                userId: "you",
                type: "holiday",
                title: "Holiday Gift Season",
                date: formatter.string(from: cal.date(byAdding: .day, value: 45, to: today)!),
                budget: 200
            ),
        ]
    }()
}
