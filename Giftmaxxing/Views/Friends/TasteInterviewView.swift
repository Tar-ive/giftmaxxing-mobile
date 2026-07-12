import SwiftUI

/// Maxi-led "Edit taste" — a short trivia-style interview that collects the
/// same signals Giftster-style forms do (interests, sizes, dislikes, gift
/// prefs), but as chat chips with Maxi. Always persists locally + PUT /me.
struct TasteInterviewView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var step = 0
    @State private var interests: Set<String> = []
    @State private var giftStyle: String?
    @State private var dislikes: Set<String> = []
    @State private var shoeSize = ""
    @State private var shirtSize = ""
    @State private var pantsSize = ""
    @State private var note = ""
    @State private var saving = false
    @State private var saved = false

    private let interestOptions = [
        "cozy", "foodie", "wellness", "tech", "fashion", "outdoors",
        "music", "books", "beauty", "home", "travel", "fitness",
        "gaming", "art", "sustainable", "luxury",
    ]
    private let styleOptions: [(id: String, label: String, hint: String)] = [
        ("thoughtful", "Thoughtful", "Experiences, handwritten notes, meaning first"),
        ("materialistic", "Stuff I want", "Things on my list — go for it"),
        ("mix", "A mix", "Surprise me with both"),
    ]
    private let dislikeOptions = [
        "candles", "mugs", "generic gift cards", "clothes without a size",
        "scents / perfume", "kitchen gadgets", "decor I didn't pick",
    ]

    private var totalSteps: Int { 5 } // interests → style → dislikes → sizes → note/save

    var body: some View {
        VStack(spacing: 0) {
            progressBar
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    maxiBubble(promptForStep)
                    stepContent
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            bottomBar
        }
        .background(Color.surface)
        .navigationTitle("Edit taste")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .onAppear {
            appState.suppressMaxiFAB()
            // Prefill from any prior interview / consult vibes.
            interests = Set(PersonalizationStore.consultVibes)
            if let sizes = PersonalizationStore.clothingSizes {
                shoeSize = sizes["shoes"] ?? ""
                shirtSize = sizes["shirt"] ?? ""
                pantsSize = sizes["pants"] ?? ""
            }
            giftStyle = PersonalizationStore.giftStyle
            dislikes = Set(PersonalizationStore.dislikes)
            note = PersonalizationStore.giftNote ?? ""
        }
        .onDisappear { appState.unsuppressMaxiFAB() }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.cream)
                Capsule()
                    .fill(Color.coral)
                    .frame(width: geo.size.width * CGFloat(step + 1) / CGFloat(totalSteps))
            }
        }
        .frame(height: 4)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var promptForStep: String {
        switch step {
        case 0: return "Quick taste check — pick a few vibes that feel like you. Tap as many as you want."
        case 1: return "When friends buy for you, what lands best?"
        case 2: return "Trivia round: what should people NEVER get you?"
        case 3: return "Sizes help friends buy clothes with confidence. Skip any you don't want to share."
        default: return "Anything else friends should know? Then I'll save this to your profile."
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0:
            chipGrid(options: interestOptions, selected: $interests)
        case 1:
            VStack(spacing: 10) {
                ForEach(styleOptions, id: \.id) { opt in
                    Button {
                        giftStyle = opt.id
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(opt.label)
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(Color.ink)
                                Text(opt.hint)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if giftStyle == opt.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.coral)
                            }
                        }
                        .padding(14)
                        .background(giftStyle == opt.id ? Color.coral.opacity(0.12) : Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
            }
        case 2:
            chipGrid(options: dislikeOptions, selected: $dislikes)
        case 3:
            VStack(spacing: 12) {
                sizeField("Shoes", text: $shoeSize, placeholder: "e.g. 10 US")
                sizeField("Casual shirt", text: $shirtSize, placeholder: "e.g. M")
                sizeField("Pants", text: $pantsSize, placeholder: "e.g. 32")
            }
        default:
            VStack(alignment: .leading, spacing: 8) {
                Text("When it comes to me and gifts…")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextField("e.g. I love experiences more than stuff", text: $note, axis: .vertical)
                    .lineLimit(3...6)
                    .padding(12)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if step > 0 {
                Button("Back") { withAnimation { step -= 1 } }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.ink)
            }
            Spacer()
            Button {
                if step < totalSteps - 1 {
                    withAnimation { step += 1 }
                } else {
                    Task { await save() }
                }
            } label: {
                HStack(spacing: 6) {
                    if saving { ProgressView().tint(.white) }
                    Text(step < totalSteps - 1 ? "Next" : (saved ? "Saved ✓" : "Save my taste"))
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .background(Color.coral)
                .clipShape(Capsule())
            }
            .disabled(saving || (step == 0 && interests.isEmpty))
            .opacity(saving || (step == 0 && interests.isEmpty) ? 0.55 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.surface)
    }

    private func maxiBubble(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Color.gradient(for: .coral))
                .frame(width: 36, height: 36)
                .overlay {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(Color.ink)
                .padding(12)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            Spacer(minLength: 24)
        }
    }

    private func chipGrid(options: [String], selected: Binding<Set<String>>) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
            ForEach(options, id: \.self) { opt in
                let on = selected.wrappedValue.contains(opt)
                Button {
                    if on { selected.wrappedValue.remove(opt) }
                    else { selected.wrappedValue.insert(opt) }
                } label: {
                    Text(opt)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(on ? Color.white : Color.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(on ? Color.coral : Color.white)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func sizeField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .padding(12)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }

        let vibeList = Array(interests).sorted()
        PersonalizationStore.consultVibes = vibeList
        PersonalizationStore.giftStyle = giftStyle
        PersonalizationStore.dislikes = Array(dislikes).sorted()
        PersonalizationStore.giftNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        var sizes: [String: String] = [:]
        if !shoeSize.isEmpty { sizes["shoes"] = shoeSize }
        if !shirtSize.isEmpty { sizes["shirt"] = shirtSize }
        if !pantsSize.isEmpty { sizes["pants"] = pantsSize }
        PersonalizationStore.clothingSizes = sizes.isEmpty ? nil : sizes

        NotificationCenter.default.post(name: .consultProfileUpdated, object: nil)

        if let uid = authManager.userId {
            do {
                let existing = try await APIClient.shared.fetchMe(userId: uid)
                var profile: [String: Any] = [
                    "name": authManager.displayName ?? existing?.name ?? "Gifter",
                    "role": "both",
                    "difficulty": "moderate",
                    "style": giftStyle ?? "thoughtful",
                    "materialisticCategories": [String](),
                    "interests": vibeList,
                    "dislikes": Array(dislikes).sorted(),
                    "clothingSizes": sizes,
                    "giftNote": PersonalizationStore.giftNote ?? "",
                    "dealPreferences": [
                        "sensitivity": "value-conscious",
                        "budgetRange": "no-limit",
                        "dealTypes": ["price-drops"],
                        "priceAlerts": false,
                    ] as [String: Any],
                    "pinterestLinks": [String](),
                    "completedAt": existing?.completedAt ?? Date().timeIntervalSince1970 * 1000,
                ]
                if let email = existing?.email ?? authManager.email { profile["email"] = email }
                try await APIClient.shared.saveMeRaw(userId: uid, profile: profile)
            } catch {
                // Local taste still applies offline.
            }
        }

        saved = true
        try? await Task.sleep(nanoseconds: 600_000_000)
        dismiss()
    }
}
