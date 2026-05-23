import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: AgentDockStore

    var body: some View {
        Form {
            Section("AgentDock") {
                LabeledContent("Processed", value: "\(store.analyses.count)")
                LabeledContent("Tool approvals", value: "Gmail, Calendar, Notion, Linear, Slack, Microsoft 365")
            }

            Section("Next connectors") {
                Toggle("Require approval before external actions", isOn: .constant(true))
                Toggle("Save original source proof", isOn: .constant(true))
            }
        }
        .padding()
    }
}
