import SwiftUI
import GiftmaxxingDesignSystem

// Global "saved to a Gift Board" feedback. The picker fires an event here on
// every add; ContentView renders the toast above the tab bar with a View link
// that deep-links into the board (AppState.openBoard). This is the moment that
// teaches users WHERE boards live — the old flow ended on a silent checkmark.
@MainActor
final class BoardToastCenter: ObservableObject {
    static let shared = BoardToastCenter()

    struct Event: Equatable, Identifiable {
        let id = UUID()
        let boardId: String
        let boardName: String
    }

    @Published var event: Event?

    private var hideTask: Task<Void, Never>?

    func show(boardId: String, boardName: String) {
        hideTask?.cancel()
        withAnimation(.snappy) {
            event = Event(boardId: boardId, boardName: boardName)
        }
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func hide() {
        hideTask?.cancel()
        withAnimation(.snappy) { event = nil }
    }
}

// One-time "your boards live here" pointer at the Swipe tab, shown after the
// first save if the user didn't tap View on the toast.
enum BoardsHint {
    private static let seenKey = "giftmaxxing_boards_hint_seen"

    static var seen: Bool {
        get { UserDefaults.standard.bool(forKey: seenKey) }
        set { UserDefaults.standard.set(newValue, forKey: seenKey) }
    }
}

struct BoardSavedToast: View {
    let event: BoardToastCenter.Event
    var onView: () -> Void

    var body: some View {
        HStack(spacing: ThemeSpacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.success)
            Text("Saved to \(event.boardName)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.ink)
                .lineLimit(1)
            Spacer(minLength: ThemeSpacing.xs)
            Button(action: onView) {
                Text("View")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.coral)
                    .padding(.horizontal, ThemeSpacing.sm)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View \(event.boardName)")
        }
        .padding(.leading, ThemeSpacing.md)
        .padding(.trailing, ThemeSpacing.xs)
        .padding(.vertical, ThemeSpacing.xs)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.lg, style: .continuous))
        .shadow(
            color: ThemeElevation.floating.color,
            radius: ThemeElevation.floating.radius,
            y: ThemeElevation.floating.y
        )
        .padding(.horizontal, ThemeSpacing.md)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

struct BoardsHintCallout: View {
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                Text("Your Gift Boards live here")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, ThemeSpacing.sm)
                    .padding(.vertical, ThemeSpacing.xs)
                    .background(Color.ink.opacity(0.9))
                    .clipShape(Capsule())
                Image(systemName: "arrowtriangle.down.fill")
                    .font(.caption2)
                    .foregroundStyle(Color.ink.opacity(0.9))
                    .offset(y: -2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Your Gift Boards live in the You tab")
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}
