import SwiftUI

// Light / dark / follow-the-system, chosen in Settings and applied at the app
// root. Every color the app draws resolves through the tokens in Theme.swift,
// so flipping this themes every screen at once.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var icon: String {
        switch self {
        case .system: return "iphone"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

@MainActor
final class AppearanceStore: ObservableObject {
    static let shared = AppearanceStore()

    private static let key = "giftmaxxing_appearance_mode"

    @Published var mode: AppearanceMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: Self.key) }
    }

    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.key)
        mode = stored.flatMap(AppearanceMode.init(rawValue:)) ?? .system
    }
}
