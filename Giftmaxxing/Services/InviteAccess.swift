import Foundation
import SwiftUI

// Invite gate for the social half of the app.
//
// Giftmaxxing's default surface is a gift SEARCH tool: Home, Swipe, Search,
// Maxi, cart. Everything that only pays off with other people already in the
// app — Circles, gift pools, group gifts, swipe challenges, friends/DMs,
// sharing a Gift Board — reads as an empty social network to a new user, so
// it ships hidden behind an invite code.
//
// Redeeming a code unlocks the Circles tab and every gated entry point; the
// unlock is DEVICE-local and account-scoped (AccountLocalState clears it on
// sign-out / account switch), because an invite belongs to a person, not to
// a phone.
@MainActor
final class InviteAccess: ObservableObject {
    static let shared = InviteAccess()

    nonisolated static let unlockedKey = "giftmaxxing_invite_unlocked"
    nonisolated static let redeemedKey = "giftmaxxing_invite_code"

    @Published private(set) var isUnlocked: Bool

    private init() {
        isUnlocked = Self.isUnlockedNow
    }

    // Isolation-free read for call sites that aren't main-actor bound (view
    // geometry helpers, static tour steps). Same answer as `isUnlocked`.
    nonisolated static var isUnlockedNow: Bool {
        #if DEBUG
        // UI automation (Maestro) drives the invite-only surfaces directly:
        //   - launchApp: { arguments: { e2eUnlockCircles: true } }
        if UserDefaults.standard.bool(forKey: "e2eUnlockCircles") { return true }
        #endif
        return UserDefaults.standard.bool(forKey: unlockedKey)
    }

    // Accepted codes come from Info.plist (`CirclesInviteCodes`, comma
    // separated) so a new cohort code is a one-line project.yml change, with a
    // built-in fallback so a mis-generated project can't lock invitees out.
    private static var acceptedCodes: Set<String> {
        let configured = (Bundle.main.object(forInfoDictionaryKey: "CirclesInviteCodes") as? String) ?? ""
        let codes = configured
            .split(separator: ",")
            .map { normalize(String($0)) }
            .filter { !$0.isEmpty }
        return codes.isEmpty ? ["GIFTCIRCLE"] : Set(codes)
    }

    private static func normalize(_ code: String) -> String {
        code.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .uppercased()
    }

    /// Returns true when the code is valid; unlocks the social surfaces.
    @discardableResult
    func redeem(_ code: String) -> Bool {
        let normalized = Self.normalize(code)
        guard Self.acceptedCodes.contains(normalized) else { return false }
        UserDefaults.standard.set(true, forKey: Self.unlockedKey)
        UserDefaults.standard.set(normalized, forKey: Self.redeemedKey)
        isUnlocked = true
        AnalyticsEngine.shared.trackScreenView(screen: "invite_unlocked")
        return true
    }

    /// Sign-out / account switch — the next person on this device starts locked.
    func lock() {
        UserDefaults.standard.removeObject(forKey: Self.unlockedKey)
        UserDefaults.standard.removeObject(forKey: Self.redeemedKey)
        isUnlocked = false
    }
}

// The one place a locked user can get in: paste the code a friend sent.
struct InviteCodeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var invites = InviteAccess.shared
    @State private var code = ""
    @State private var failed = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Circles is invite-only while we're in early access — gifting together, shared calendars, pools.")
                    .font(.bodyMedium)
                    .foregroundStyle(.secondary)

                TextField("Invite code", text: $code)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .onChange(of: code) { _, _ in failed = false }

                if failed {
                    Text("That code isn't valid. Check it with whoever invited you.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button {
                    if invites.redeem(code) {
                        dismiss()
                    } else {
                        failed = true
                    }
                } label: {
                    HStack {
                        Spacer()
                        Text("Unlock Circles").font(.labelBold)
                        Spacer()
                    }
                    .padding(.vertical, 13)
                    .background(Color.coral)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                }
                .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty)

                Spacer()
            }
            .padding(16)
            .background(Color.surface)
            .navigationTitle("Have an invite?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .sensoryFeedback(.success, trigger: invites.isUnlocked)
    }
}
