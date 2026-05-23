import SwiftUI

@main
struct AgentDockApp: App {
    @NSApplicationDelegateAdaptor(AgentDockAppDelegate.self) private var appDelegate
    @StateObject private var store: AgentDockStore
    @StateObject private var preferences: AppPreferences
    private let environment: AppEnvironment

    init() {
        let environment = AppEnvironment.shared
        self.environment = environment
        _store = StateObject(wrappedValue: environment.store)
        _preferences = StateObject(wrappedValue: environment.preferences)
    }

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(store)
                .environmentObject(preferences)
                .modelContainer(environment.modelContainer)
                .frame(width: 460, height: 380)
        }
    }
}
