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
            SourceProof.self,
            StoredAnalysis.self
        ])

        do {
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // SwiftData container creation is a startup-critical failure.
            // Log to crash reporter async and fall back to an in-memory container so the
            // app can still function this session (data will not persist).
            Task { await CrashReporter.shared.log(error, context: "model-container-init") }
            let fallbackConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            modelContainer = (try? ModelContainer(for: schema, configurations: [fallbackConfig]))
                ?? { fatalError("SwiftData failed to initialise even an in-memory container: \(error)") }()
        }

        store.attachModelContext(ModelContext(modelContainer))
    }
}
