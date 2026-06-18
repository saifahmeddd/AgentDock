import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: AgentDockStore
    @EnvironmentObject private var preferences: AppPreferences

    var body: some View {
        Form {
            Section("OpenRouter API") {
                SecureField(preferences.maskedKeyLabel, text: $preferences.apiKeyDraft)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button {
                        Task { await preferences.saveDraftKey() }
                    } label: {
                        Label("Save Key", systemImage: "key")
                    }
                    .disabled(preferences.apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button {
                        Task { await preferences.verify() }
                    } label: {
                        Label("Verify", systemImage: "checkmark.seal")
                    }
                    .buttonStyle(.borderedProminent)

                    VerificationView(status: preferences.verificationStatus)
                }
            }

            Section {
                Picker("Model", selection: $preferences.selectedModel) {
                    ForEach(OpenRouterModel.allCases) { model in
                        VStack(alignment: .leading) {
                            Text(model.displayName)
                            Text(model.costSummary)
                                .font(.caption)
                                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                        }
                        .tag(model)
                    }
                }
                .pickerStyle(.radioGroup)

                HStack {
                    Image(systemName: "info.circle")
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    Text("Cost estimates are client-side approximations. Live pricing from OpenRouter may differ.")
                        .font(.caption)
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("Model")
            }

            Section("Connectors") {
                ForEach(ActionTool.allCases) { tool in
                    ConnectorSettingRow(tool: tool, state: preferences.connectorState(for: tool))
                }
            }

            Section("AgentDock") {
                LabeledContent("Session analyses", value: "\(store.analyses.count)")
                LabeledContent("Hotkey", value: "Option+Space")
                Button("Open Source Proofs Folder") {
                    Task {
                        let dir = await SourceArchive.shared.applicationSupportDirectory()
                        NSWorkspace.shared.open(dir)
                    }
                }
                Button("Open Log File") {
                    if let logsBase = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first {
                        let logDir = logsBase
                            .appendingPathComponent("Logs")
                            .appendingPathComponent("AgentDock")
                        NSWorkspace.shared.open(logDir)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - VerificationView

private struct VerificationView: View {
    let status: VerificationStatus

    var body: some View {
        Group {
            switch status {
            case .unknown:
                Text("Not verified")
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            case .verifying:
                HStack(spacing: 5) {
                    ProgressView().controlSize(.small)
                    Text("Verifying…")
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                }
            case .valid(let message):
                Label(message, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .invalid(let message):
                Label(message, systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }
        }
        .font(.caption)
    }
}

// MARK: - ConnectorSettingRow

private struct ConnectorSettingRow: View {
    let tool: ActionTool
    let state: ConnectorAuthState

    var body: some View {
        HStack {
            Circle()
                .fill(indicatorColor)
                .frame(width: 8, height: 8)
            Text(tool.rawValue)
            Spacer()
            HStack(spacing: 4) {
                Text(stateLabel)
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                if state == .notConnected {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                }
            }
            .font(.caption)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if state == .notConnected {
                openConnectorInfo(for: tool)
            }
        }
    }

    private var stateLabel: String {
        switch state {
        case .notConnected: "Not connected"
        case .connectedViaSystem: "Ready (system)"
        case .connected: "Connected"
        }
    }

    private var indicatorColor: Color {
        switch state {
        case .notConnected: Color(nsColor: .tertiaryLabelColor)
        case .connectedViaSystem, .connected:
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

    private func openConnectorInfo(for tool: ActionTool) {
        // OAuth connector setup will open the appropriate configuration sheet.
        // For now, open the relevant developer portal so the user can register an app.
        let urls: [ActionTool: String] = [
            .notion: "https://www.notion.so/my-integrations",
            .linear: "https://linear.app/settings/api",
            .slack: "https://api.slack.com/apps",
            .microsoft365: "https://portal.azure.com/#view/Microsoft_AAD_RegisteredApps/ApplicationsListBlade"
        ]
        if let urlString = urls[tool], let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
