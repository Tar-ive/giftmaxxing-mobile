import SwiftUI

// The share-extension loop, step two: "Start a gift pool" was tapped on a
// captured Instagram/Pinterest post — prefill a pool with that image, ask
// only for the essentials (who, what, target), then hand off to a share
// sheet so friends get pulled in immediately.
struct CreatePoolFromCaptureView: View {
    let image: UIImage?
    let sourceURL: String?
    // Pledging from the feed — prefills title/target and attaches the product.
    var product: Product? = nil

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var authManager: AuthManager
    @ObservedObject private var store = PoolsStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var forUser = ""
    @State private var targetAmount = ""
    @State private var createdPool: Pool?
    @State private var poolForFriendInvite: Pool?

    private var parsedTarget: Double {
        Double(targetAmount.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && parsedTarget > 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 160, height: 160)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                            .padding(.top, 8)
                    } else if let product {
                        ZStack {
                            Color.gradient(for: product.grad)
                            Text(product.emoji).font(.system(size: 48))
                            if let productImage = product.image {
                                CachedAsyncImage(url: productImage, width: 400)
                            }
                        }
                        .frame(width: 160, height: 160)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .padding(.top, 8)
                    }

                    if let createdPool {
                        successState(createdPool)
                    } else {
                        formFields
                    }
                }
                .padding(.horizontal, 18)
            }
            .background(Color.surface)
            .navigationTitle("Start a gift pool")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                // Feed pledge → sensible defaults the user can still edit.
                if let product, title.isEmpty {
                    title = product.name
                    if targetAmount.isEmpty, product.price > 0 {
                        targetAmount = String(Int(product.price.rounded()))
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(createdPool == nil ? "Cancel" : "Done") {
                        dismiss()
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var formFields: some View {
        VStack(spacing: 12) {
            field("What's the gift?", text: $title, placeholder: "e.g. That ceramic vase she posted")
            field("Who's it for?", text: $forUser, placeholder: "e.g. Maya")

            VStack(alignment: .leading, spacing: 6) {
                Text("Target amount")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.ink)
                TextField("$ e.g. 80", text: $targetAmount)
                    .keyboardType(.decimalPad)
                    .padding(12)
                    .background(Color.cream)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Button {
                let imageFile = image.flatMap { PoolsStore.saveCaptureImage($0) }
                createdPool = store.create(
                    title: title.trimmingCharacters(in: .whitespaces),
                    forUser: forUser.trimmingCharacters(in: .whitespaces),
                    occasion: "",
                    targetAmount: parsedTarget,
                    product: product,
                    localImageFile: imageFile,
                    sourceUrl: sourceURL
                )
            } label: {
                Text("Create pool")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(isValid ? Color.coral : Color.coral.opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(!isValid)
            .padding(.top, 4)
        }
    }

    // Pool exists — the next move is social: pull friends in.
    private func successState(_ pool: Pool) -> some View {
        VStack(spacing: 14) {
            Text("Pool created")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.ink)

            Text("\(pool.title) — $\(Int(pool.targetAmount)) target. Now bring in the crew.")
                .font(.bodyMedium)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            ShareLink(
                item: InviteLink.buildPoolURL(
                    inviterName: appState.currentUser?.name ?? "A friend",
                    pool: pool
                ) ?? URL(string: InviteLink.siteURL)!,
                subject: Text("Gift pool: \(pool.title)"),
                message: Text("Chip in for \(pool.title)\(pool.forUser.isEmpty ? "" : " for \(pool.forUser)") — $\(Int(pool.targetAmount)) target. 🎁")
            ) {
                HStack(spacing: 8) {
                    Image(systemName: "person.2.fill")
                    Text("Share pool invite")
                }
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.coral)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            Button {
                poolForFriendInvite = pool
            } label: {
                Label("Invite a friend in chat", systemImage: "message.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.coral)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.coral.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            Button {
                dismiss()
            } label: {
                Text("View on Home")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.coral)
            }
        }
        .padding(.top, 6)
        .sheet(item: $poolForFriendInvite) { pool in
            PoolInviteFriendsSheet(
                pool: pool,
                inviterName: appState.currentUser?.name ?? authManager.displayName ?? "A friend"
            )
        }
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.ink)
            TextField(placeholder, text: text)
                .padding(12)
                .background(Color.cream)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}
