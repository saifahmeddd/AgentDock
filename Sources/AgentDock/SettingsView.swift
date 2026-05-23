import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: AgentDockStore
    @EnvironmentObject private var preferences: AppPreferences

    var body: some View {
        Form {
            Section("OpenRouter") {
                SecureField(preferences.maskedKeyLabel, text: $preferences.apiKeyDraft)
                    .textFieldStyle(.roundedBorder)

                Picker("Model", selection: $preferences.selectedModel) {
                    ForEach(OpenRouterModel.allCases) { model in
                        Text(model.displayName)
                            .tag(model)
                    }
                }

                HStack {
                    Button {
                        Task {
                            await preferences.saveDraftKey()
                        }
                    } label: {
                        Label("Save Key", systemImage: "key")
                    }

                    Button {
                        Task {
                            await preferences.verify()
                        }
                    } label: {
                        Label("Verify", systemImage: "checkmark.seal")
                    }
                    .buttonStyle(.borderedProminent)

                    VerificationView(status: preferences.verificationStatus)
                }
            }

            Section("AgentDock") {
                LabeledContent("Processed", value: "\(store.analyses.count)")
                LabeledContent("Default model", value: OpenRouterModel.grokMini.rawValue)
                LabeledContent("Source proof", value: "~/Library/Application Support/AgentDock/")
            }

            Section("Connectors") {
                ConnectorSettingRow(tool: .gmail, state: "Connected via mailto")
                ConnectorSettingRow(tool: .calendar, state: "Connected via EventKit")
                ConnectorSettingRow(tool: .notion, state: "Connect")
                ConnectorSettingRow(tool: .linear, state: "Connect")
                ConnectorSettingRow(tool: .slack, state: "Connect")
                ConnectorSettingRow(tool: .microsoft365, state: "Connect")
            }
        }
        .padding()
    }
}

private struct VerificationView: View {
    let status: VerificationStatus

    var body: some View {
        switch status {
        case .unknown:
            Text("Not verified")
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
        case .verifying:
            ProgressView()
                .controlSize(.small)
        case .valid(let message):
            Label(message, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .invalid(let message):
            Label(message, systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }
}

private struct ConnectorSettingRow: View {
    let tool: ActionTool
    let state: String

    var body: some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
            Text(tool.rawValue)
            Spacer()
            Text(state)
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
        }
    }

    private var color: Color {
        switch tool {
        case .gmail: .red
        case .calendar: .green
        case .notion: Color(nsColor: .labelColor)
        case .linear: .purple
        case .slack: .blue
        case .microsoft365: .orange
        }
    }
}
