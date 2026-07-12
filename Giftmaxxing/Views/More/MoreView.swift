import SwiftUI

struct MoreView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var pushManager: PushManager
    @EnvironmentObject private var syncEngine: SyncEngine
    @State private var showSignIn = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // User header
                    if authManager.isAuthenticated {
                        VStack(spacing: 8) {
                            Circle()
                                .fill(Color.gradient(for: .coral))
                                .frame(width: 72, height: 72)
                                .overlay {
                                    Text(String(authManager.displayName?.prefix(1) ?? "?"))
                                        .font(.system(size: 28, weight: .bold))
                                        .foregroundStyle(.white)
                                }

                            Text(authManager.displayName ?? "Giftmaxxer")
                                .font(.displaySmall)
                                .foregroundStyle(Color.ink)

                            if let email = authManager.email {
                                Text(email)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if let lastSync = syncEngine.lastSyncDate {
                                Text("Last synced \(lastSync, style: .relative) ago")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 16)
                    } else {
                        VStack(spacing: 12) {
                            Text("Sign in to unlock all features")
                                .font(.bodyMedium)
                                .foregroundStyle(.secondary)

                            Button("Sign in with Apple") {
                                showSignIn = true
                            }
                            .font(.labelBold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.ink)
                            .clipShape(Capsule())
                        }
                        .padding(.vertical, 16)
                    }

                    // Your gifting life. (Group gifting + challenges AND events
                    // & reminders live in the Circles tab — dates belong with
                    // the people they're for. This screen is profile + shopping.)
                    VStack(spacing: 2) {
                        MoreSectionHeader(title: "Your gifting")

                        MoreRow(icon: "person.2.fill", title: "Friends", subtitle: "Discover, connect, message") {
                            FriendsView()
                        }

                        MoreRow(icon: "sparkles", title: "Edit taste", subtitle: "Maxi asks — sizes, vibes, dislikes") {
                            TasteInterviewView()
                        }

                        MoreRow(icon: "bag.fill", title: "Shop", subtitle: "Curated picks") {
                            ShopView()
                        }
                    }

                    // Settings
                    VStack(spacing: 2) {
                        MoreSectionHeader(title: "Settings")

                        Button(action: {
                            Task { await pushManager.requestPermission() }
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "bell.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(Color.coral)
                                    .frame(width: 28)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Push Notifications")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(Color.ink)
                                    Text(pushManager.isRegistered ? "Enabled" : "Tap to enable")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if pushManager.isRegistered {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                } else {
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Color.surface)
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            Task {
                                await syncEngine.performFullSync(
                                    context: DataController.shared.mainContext,
                                    userId: authManager.userId
                                )
                            }
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 16))
                                    .foregroundStyle(Color.coral)
                                    .frame(width: 28)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Sync Now")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(Color.ink)
                                    if syncEngine.isSyncing {
                                        Text("Syncing...")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else if let lastSync = syncEngine.lastSyncDate {
                                        Text("Last: \(lastSync, style: .relative) ago")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                if syncEngine.isSyncing {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Color.surface)
                        }
                        .buttonStyle(.plain)
                    }

                    // Account
                    if authManager.isAuthenticated {
                        VStack(spacing: 2) {
                            MoreSectionHeader(title: "Account")

                            Button(action: {
                                DataController.shared.clearAllData()
                                authManager.signOut()
                            }) {
                                HStack(spacing: 12) {
                                    Image(systemName: "rectangle.portrait.and.arrow.right")
                                        .font(.system(size: 16))
                                        .foregroundStyle(.red)
                                        .frame(width: 28)

                                    Text("Sign Out")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(.red)

                                    Spacer()
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(Color.surface)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Privacy
                    VStack(spacing: 2) {
                        MoreSectionHeader(title: "Legal")

                        MoreRow(icon: "hand.raised.fill", title: "Privacy Policy", subtitle: "Your data rights") {
                            PrivacyView()
                        }
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 14)
            }
            .background(Color.cream)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("More")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                }
            }
        }
        .sheet(isPresented: $showSignIn) {
            SignInView(showSignIn: $showSignIn)
                .environmentObject(authManager)
        }
    }
}

struct MoreSectionHeader: View {
    let title: String

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(1)
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }
}

struct MoreRow<Destination: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(Color.coral)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.ink)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.surface)
        }
        .buttonStyle(.plain)
    }
}

struct PrivacyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Privacy Policy")
                    .font(.displayMedium)

                Text("Giftmaxxing respects your privacy. We collect only the data necessary to provide personalized gift recommendations.")
                    .font(.bodyLarge)

                Text("Data We Collect")
                    .font(.displaySmall)

                Text("Your interactions (likes, saves, swipes) help us understand your taste for gift recommendations. This data is stored securely on AWS and is never sold to third parties.")
                    .font(.bodyLarge)

                Text("Data Ownership")
                    .font(.displaySmall)

                Text("You own your data. You can request deletion of all your data at any time by contacting support or using the Sign Out option, which clears all local data.")
                    .font(.bodyLarge)

                Text("Amazon Affiliate Links")
                    .font(.displaySmall)

                Text("When you purchase products through our links, we may earn a small commission from Amazon Associates. This does not affect the price you pay.")
                    .font(.bodyLarge)
            }
            .padding(20)
        }
        .navigationTitle("Privacy")
    }
}
