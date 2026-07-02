import Foundation
import SwiftData

@MainActor
final class DataController {
    static let shared = DataController()

    let container: ModelContainer
    var mainContext: ModelContext { container.mainContext }

    private init() {
        let schema = Schema([
            CachedPost.self,
            CachedInteraction.self,
            CachedEvent.self,
            PendingAction.self,
        ])

        let config = ModelConfiguration(
            "Giftmaxxing",
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    func clearAllData() {
        try? mainContext.delete(model: CachedPost.self)
        try? mainContext.delete(model: CachedInteraction.self)
        try? mainContext.delete(model: CachedEvent.self)
        try? mainContext.delete(model: PendingAction.self)
        try? mainContext.save()
    }
}
