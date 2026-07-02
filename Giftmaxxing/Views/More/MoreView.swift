import SwiftUI

struct MoreFeature: Identifiable {
    let id: String
    var title: String
    var description: String
    var icon: String
    var color: Color
    var destination: MoreDestination
    var badge: String?
}

enum MoreDestination: String {
    case maxi
    case pools
    case shop
    case ideas
    case milestones
    case settings
    case drops
    case cart
    case recommendations
}

struct MoreView: View {
    @EnvironmentObject private var appState: AppState

    private let primaryFeatures: [MoreFeature] = [
        MoreFeature(id: "maxi", title: "Ask Maxi", description: "AI gift concierge", icon: "sparkles", color: .coral, destination: .maxi, badge: "AI"),
        MoreFeature(id: "pools", title: "Gift Pools", description: "Split costs with friends", icon: "person.3.fill", color: Color(hex: "#7C5CFC"), destination: .pools),
        MoreFeature(id: "shop", title: "Shop", description: "Amazon picks & deals", icon: "bag.fill", color: Color(hex: "#FF9900"), destination: .shop),
        MoreFeature(id: "ideas", title: "Gift Ideas", description: "Curated inspiration", icon: "lightbulb.fill", color: Color(hex: "#34C759"), destination: .ideas),
        MoreFeature(id: "drops", title: "Drops", description: "Bundled deals", icon: "flame.fill", color: Color(hex: "#FF6B35"), destination: .drops),
        MoreFeature(id: "recs", title: "For You", description: "Personalized picks", icon: "heart.text.square.fill", color: Color(hex: "#AF52DE"), destination: .recommendations),
    ]

    private let secondaryFeatures: [MoreFeature] = [
        MoreFeature(id: "milestones", title: "Milestones", description: "Track gifting goals", icon: "trophy.fill", color: Color(hex: "#FFD700"), destination: .milestones),
        MoreFeature(id: "cart", title: "Cart", description: "Your saved items", icon: "cart.fill", color: Color(hex: "#007AFF"), destination: .cart),
        MoreFeature(id: "settings", title: "Settings", description: "Account & preferences", icon: "gearshape.fill", color: .gray, destination: .settings),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // User header
                    UserHeaderCard()

                    // Quick stats
                    QuickStatsRow()

                    // Primary features
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Features")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.ink)
                            .padding(.horizontal, 16)

                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12),
                        ], spacing: 12) {
                            ForEach(primaryFeatures) { feature in
                                FeatureCard(feature: feature)
                            }
                        }
                        .padding(.horizontal, 16)
                    }

                    // Secondary features
                    VStack(alignment: .leading, spacing: 12) {
                        Text("More")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.ink)
                            .padding(.horizontal, 16)

                        ForEach(secondaryFeatures) { feature in
                            SecondaryFeatureRow(feature: feature)
                        }
                        .padding(.horizontal, 16)
                    }

                    // Maxi banner
                    MaxiBannerCard()
                        .padding(.horizontal, 16)

                    // Footer links
                    VStack(spacing: 8) {
                        NavigationLink(destination: PrivacyView()) {
                            Text("Privacy Policy")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text("giftmaxxing v1.0")
                            .font(.caption)
                            .foregroundStyle(.secondary.opacity(0.6))
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
                .padding(.top, 16)
            }
            .background(Color.surface)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        MaxiIcon(size: 24)
                        Text("Giftmaxxing")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                    }
                }
            }
        }
    }
}

struct UserHeaderCard: View {
    var body: some View {
        HStack(spacing: 14) {
            AvatarView(name: "You", grad: .coral, size: 56)

            VStack(alignment: .leading, spacing: 2) {
                Text("Welcome back!")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.ink)
                Text("@you")
                    .font(.bodyMedium)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            NavigationLink(destination: SettingsView()) {
                Image(systemName: "gearshape")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color.cream)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }
}

struct QuickStatsRow: View {
    private let stats: [(label: String, value: String, icon: String)] = [
        ("Gifts given", "12", "gift.fill"),
        ("Pools", "3", "person.3.fill"),
        ("Saved", "24", "bookmark.fill"),
    ]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(stats, id: \.label) { stat in
                VStack(spacing: 6) {
                    Image(systemName: stat.icon)
                        .font(.system(size: 16))
                        .foregroundStyle(Color.coral)
                    Text(stat.value)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.ink)
                    Text(stat.label)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.cream)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(.horizontal, 16)
    }
}

struct FeatureCard: View {
    let feature: MoreFeature

    var body: some View {
        NavigationLink(destination: destinationView) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: feature.icon)
                        .font(.system(size: 20))
                        .foregroundStyle(feature.color)

                    Spacer()

                    if let badge = feature.badge {
                        Text(badge)
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.coral)
                            .clipShape(Capsule())
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(feature.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.ink)
                    Text(feature.description)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .background(Color.cream)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var destinationView: some View {
        switch feature.destination {
        case .maxi: MaxiView()
        case .pools: PoolsView()
        case .shop: ShopView()
        case .settings: SettingsView()
        default: PlaceholderView(title: feature.title)
        }
    }
}

struct SecondaryFeatureRow: View {
    let feature: MoreFeature

    var body: some View {
        NavigationLink(destination: destinationView) {
            HStack(spacing: 14) {
                Image(systemName: feature.icon)
                    .font(.system(size: 18))
                    .foregroundStyle(feature.color)
                    .frame(width: 36, height: 36)
                    .background(feature.color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 1) {
                    Text(feature.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.ink)
                    Text(feature.description)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color.cream)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var destinationView: some View {
        switch feature.destination {
        case .settings: SettingsView()
        default: PlaceholderView(title: feature.title)
        }
    }
}

struct MaxiBannerCard: View {
    var body: some View {
        NavigationLink(destination: MaxiView()) {
            HStack(spacing: 14) {
                MaxiIcon(size: 44)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("Ask Maxi")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                        Text("AI")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(Color.coral)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.white)
                            .clipShape(Capsule())
                    }
                    Text("Your AI gift concierge — find the perfect gift in seconds")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.85))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(16)
            .background(
                LinearGradient(
                    colors: [Color.coral, Color(hex: "#FF9A76")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

struct PlaceholderView: View {
    let title: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "hammer.fill")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("\(title)")
                .font(.displaySmall)
            Text("Coming soon")
                .font(.bodyMedium)
                .foregroundStyle(.secondary)
        }
        .navigationTitle(title)
    }
}

struct SettingsView: View {
    var body: some View {
        List {
            Section("Account") {
                HStack {
                    Text("Name")
                    Spacer()
                    Text("You")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Email")
                    Spacer()
                    Text("you@example.com")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Preferences") {
                Toggle("Push notifications", isOn: .constant(true))
                Toggle("Email reminders", isOn: .constant(true))
                Toggle("Event countdown alerts", isOn: .constant(true))
            }

            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0.0")
                        .foregroundStyle(.secondary)
                }
                NavigationLink("Privacy Policy", destination: PrivacyView())
                NavigationLink("Terms of Service", destination: PlaceholderView(title: "Terms"))
            }

            Section {
                Button("Sign Out") {}
                    .foregroundStyle(.red)
            }
        }
        .navigationTitle("Settings")
    }
}

struct PrivacyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Privacy Policy")
                    .font(.displayLarge)

                Text("Last updated: July 2025")
                    .font(.bodyMedium)
                    .foregroundStyle(.secondary)

                Group {
                    Text("Data Ownership")
                        .font(.displaySmall)
                    Text("Your data belongs to you. Giftmaxxing stores only what's necessary to provide the service: your profile, saved items, event dates, and interaction history.")
                        .font(.bodyMedium)

                    Text("PII Redaction")
                        .font(.displaySmall)
                    Text("We do not sell or share personal information with third parties for advertising purposes. Affiliate links connect to Amazon's Associates program; Amazon handles all purchase data independently.")
                        .font(.bodyMedium)

                    Text("No Third-Party Tracking")
                        .font(.displaySmall)
                    Text("We do not use third-party analytics or tracking services. Your browsing behavior within the app stays within the app.")
                        .font(.bodyMedium)
                }
            }
            .padding(20)
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}
