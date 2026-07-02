import SwiftUI

// Group-gift messages — iOS port of web/app/feed/messages/page.tsx backed by
// the same seeded chats (web/lib/social.ts GROUP_CHATS), persisted locally so
// sent messages survive relaunch (web uses localStorage).
struct ChatMessage: Identifiable, Codable, Hashable {
    let id: String
    var user: String
    var text: String
    var time: String
}

struct GroupChat: Identifiable, Codable, Hashable {
    let id: String
    var forUser: String
    var occasion: String
    var countdown: String?
    var members: [String]
    var messages: [ChatMessage]

    var title: String {
        let name = SocialUsers.name(for: forUser)
        switch occasion {
        case "birthday": return "\(name)'s Birthday"
        case "farewell": return "\(name)'s Farewell"
        case "housewarming": return "\(name)'s Housewarming"
        case "anniversary": return "\(name)'s Anniversary"
        default: return occasion.isEmpty ? name : "\(name) — \(occasion)"
        }
    }

    var memberNames: String {
        members.filter { $0 != "you" }
            .map { SocialUsers.name(for: $0).components(separatedBy: " ").first ?? $0 }
            .joined(separator: ", ")
    }
}

// Minimal port of web/lib/social.ts USERS (names + avatar gradients).
enum SocialUsers {
    static let all: [String: (name: String, grad: GradientStyle)] = [
        "you": ("You", .coral),
        "maxi": ("Maxi", .coral),
        "maya": ("Maya Reyes", .rose),
        "jules": ("Jules Park", .lilac),
        "sam": ("Sam Okafor", .sky),
        "noor": ("Noor Haddad", .butter),
        "theo": ("Theo Lin", .sage),
        "ivy": ("Ivy Castellano", .rose),
        "remy": ("Remy Adebayo", .peach),
    ]

    static func name(for id: String) -> String { all[id]?.name ?? id }
    static func grad(for id: String) -> GradientStyle { all[id]?.grad ?? .coral }
}

@MainActor
final class MessagesStore: ObservableObject {
    @Published var chats: [GroupChat] = []

    private static let storageKey = "giftmaxxing_messages"

    init() {
        load()
    }

    func load() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode([GroupChat].self, from: data) {
            chats = saved
        } else {
            chats = Self.seeds
        }
    }

    func send(_ text: String, to chatId: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let idx = chats.firstIndex(where: { $0.id == chatId }) else { return }
        chats[idx].messages.append(ChatMessage(
            id: "msg-\(Int(Date().timeIntervalSince1970 * 1000))",
            user: "you",
            text: trimmed,
            time: "now"
        ))
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(chats) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    // Seed conversations — mirror of web/lib/social.ts GROUP_CHATS.
    static let seeds: [GroupChat] = [
        GroupChat(id: "gc_maya", forUser: "maya", occasion: "birthday", countdown: "4d",
                  members: ["you", "jules", "noor", "sam"],
                  messages: [
                    ChatMessage(id: "m1", user: "jules", text: "Should we pool for that camera she's been eyeing?", time: "2h"),
                    ChatMessage(id: "m2", user: "noor", text: "Yes! I can chip in $30", time: "1h"),
                    ChatMessage(id: "m3", user: "sam", text: "Count me in. What's the total?", time: "45m"),
                    ChatMessage(id: "m4", user: "you", text: "It's $89. If we split 4 ways that's ~$22 each", time: "30m"),
                    ChatMessage(id: "m5", user: "jules", text: "Perfect. I'll order it tonight", time: "12m"),
                  ]),
        GroupChat(id: "gc_sam", forUser: "sam", occasion: "farewell", countdown: nil,
                  members: ["you", "maya", "jules", "theo"],
                  messages: [
                    ChatMessage(id: "m6", user: "maya", text: "Sam's going to Lisbon! Should we get him something travel-related?", time: "1d"),
                    ChatMessage(id: "m7", user: "theo", text: "What about those noise-cancelling buds he wanted?", time: "1d"),
                    ChatMessage(id: "m8", user: "you", text: "Good idea. Or a travel journal?", time: "22h"),
                    ChatMessage(id: "m9", user: "jules", text: "Let's do both! Travel journal + a nice pen", time: "20h"),
                  ]),
        GroupChat(id: "gc_noor", forUser: "noor", occasion: "birthday", countdown: "11d",
                  members: ["you", "maya", "remy"],
                  messages: [
                    ChatMessage(id: "m10", user: "maya", text: "Noor's birthday is coming up. She's really into plants lately", time: "3d"),
                    ChatMessage(id: "m11", user: "remy", text: "I saw this amazing terrarium kit for $45", time: "2d"),
                    ChatMessage(id: "m12", user: "you", text: "That's perfect for her apartment!", time: "1d"),
                  ]),
        GroupChat(id: "gc_ivy", forUser: "ivy", occasion: "anniversary", countdown: "18d",
                  members: ["you", "theo", "maya"],
                  messages: [
                    ChatMessage(id: "m13", user: "theo", text: "Ivy and Alex's anniversary is in 18 days", time: "5d"),
                    ChatMessage(id: "m14", user: "maya", text: "She loves warm tones. What about that sunset lamp?", time: "4d"),
                    ChatMessage(id: "m15", user: "you", text: "Great call. I'll check the price", time: "3d"),
                  ]),
        GroupChat(id: "gc_theo", forUser: "theo", occasion: "just because", countdown: nil,
                  members: ["you", "ivy", "maya"],
                  messages: [
                    ChatMessage(id: "m16", user: "ivy", text: "Found a rare pressing of Theo's favorite album", time: "2d"),
                    ChatMessage(id: "m17", user: "maya", text: "He would LOVE that. How much?", time: "1d"),
                  ]),
        GroupChat(id: "gc_remy", forUser: "remy", occasion: "housewarming", countdown: nil,
                  members: ["you", "noor", "jules"],
                  messages: [
                    ChatMessage(id: "m18", user: "noor", text: "Remy just moved! We should get a housewarming gift", time: "6h"),
                    ChatMessage(id: "m19", user: "jules", text: "What about a nice candle set?", time: "3h"),
                  ]),
    ]
}

struct MessagesView: View {
    @StateObject private var store = MessagesStore()

    var body: some View {
        List {
            ForEach(store.chats) { chat in
                NavigationLink(value: chat.id) {
                    ChatRow(chat: chat)
                }
                .listRowBackground(Color.surface)
            }
        }
        .listStyle(.plain)
        .background(Color.surface)
        .navigationTitle("Messages")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: String.self) { chatId in
            if let chat = store.chats.first(where: { $0.id == chatId }) {
                ChatThreadView(chatId: chat.id, store: store)
            }
        }
        .onAppear {
            AnalyticsEngine.shared.trackScreenView(screen: "messages")
        }
    }
}

private struct ChatRow: View {
    let chat: GroupChat

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .topTrailing) {
                AvatarView(name: SocialUsers.name(for: chat.forUser), grad: SocialUsers.grad(for: chat.forUser), size: 48)
                if let countdown = chat.countdown {
                    Text(countdown)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.coral)
                        .clipShape(Capsule())
                        .offset(x: 6, y: -4)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(chat.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                    Spacer()
                    if let last = chat.messages.last {
                        Text(last.time)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(chat.memberNames)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let last = chat.messages.last {
                    let sender = last.user == "you" ? "You" : (SocialUsers.name(for: last.user).components(separatedBy: " ").first ?? last.user)
                    Text("\(sender): \(last.text)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct ChatThreadView: View {
    let chatId: String
    @ObservedObject var store: MessagesStore
    @State private var draft = ""
    @FocusState private var composerFocused: Bool

    private var chat: GroupChat? {
        store.chats.first(where: { $0.id == chatId })
    }

    var body: some View {
        VStack(spacing: 0) {
            if let chat {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(Array(chat.messages.enumerated()), id: \.element.id) { i, msg in
                                MessageBubble(
                                    message: msg,
                                    showAvatar: msg.user != "you"
                                        && (i == 0 || chat.messages[i - 1].user != msg.user)
                                )
                                .id(msg.id)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }
                    .onChange(of: chat.messages.count) { _, _ in
                        if let lastId = chat.messages.last?.id {
                            withAnimation { proxy.scrollTo(lastId, anchor: .bottom) }
                        }
                    }
                    .onAppear {
                        if let lastId = chat.messages.last?.id {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }

                // Composer
                HStack(spacing: 8) {
                    TextField("Type a message…", text: $draft)
                        .focused($composerFocused)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.surface)
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(Color.line))
                        .onSubmit(send)

                    if !draft.trimmingCharacters(in: .whitespaces).isEmpty {
                        Button(action: send) {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 40, height: 40)
                                .background(Color.coral)
                                .clipShape(Circle())
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.cream)
            }
        }
        .background(Color.surface)
        .navigationTitle(chat?.title ?? "Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let occasion = chat?.occasion, !occasion.isEmpty {
                    Text(occasion)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.coral)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.coralSoft)
                        .clipShape(Capsule())
                }
            }
        }
    }

    private func send() {
        store.send(draft, to: chatId)
        draft = ""
        composerFocused = true
    }
}

private struct MessageBubble: View {
    let message: ChatMessage
    let showAvatar: Bool

    private var isMe: Bool { message.user == "you" }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isMe { Spacer(minLength: 60) }

            if !isMe {
                Group {
                    if showAvatar {
                        AvatarView(name: SocialUsers.name(for: message.user), grad: SocialUsers.grad(for: message.user), size: 28)
                    } else {
                        Color.clear.frame(width: 28, height: 28)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                if showAvatar && !isMe {
                    Text(SocialUsers.name(for: message.user).components(separatedBy: " ").first ?? message.user)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                Text(message.text)
                    .font(.system(size: 14))
                    .foregroundStyle(isMe ? .white : Color.ink)
                Text(message.time)
                    .font(.system(size: 10))
                    .foregroundStyle(isMe ? .white.opacity(0.6) : .secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isMe ? Color.coral : Color.ink.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 16))

            if !isMe { Spacer(minLength: 60) }
        }
    }
}
