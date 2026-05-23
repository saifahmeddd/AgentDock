import Foundation
import SwiftData

@MainActor
final class AppEnvironment {
    static let shared = AppEnvironment()

    let preferences: AppPreferences
    let store: AgentDockStore
    let modelContainer: ModelContainer

    private init() {
        preferences = AppPreferences()
        store = AgentDockStore(preferences: preferences)

        let schema = Schema([
            Commitment.self,
            WaitingItem.self,
            SourceProof.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        modelContainer = try! ModelContainer(for: schema, configurations: [configuration])
        store.attachModelContext(ModelContext(modelContainer))
    }
}
