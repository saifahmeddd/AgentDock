import SwiftUI

@main
struct AgentDockApp: App {
    @StateObject private var store = AgentDockStore()

    var body: some Scene {
        MenuBarExtra {
            AgentDockPanel()
                .environmentObject(store)
        } label: {
            Label("AgentDock", systemImage: "sparkles")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(store)
                .frame(width: 420, height: 320)
        }
    }
}
