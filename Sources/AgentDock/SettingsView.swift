import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: AgentDockStore
    @EnvironmentObject private var preferences: AppPreferences

    @State private var nimStatus: CredentialStatus = .checking
    @State private var notionStatus: CredentialStatus = .checking
    @State private var linearStatus: CredentialStatus = .checking

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                dotEnvCard
                credentialStatusCard
                modelCard
                connectorsCard
                agentDockCard
            }
            .padding(20)
        }
        .task { await checkCredentials() }
    }

    // MARK: - .env instructions

    private var dotEnvCard: some View {
        SettingsCard(title: ".env Setup") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Create a \(Text(".env").font(.system(.body, design: .monospaced)).foregroundStyle(.primary)) file in the directory where you run AgentDock:")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)

                Text("""
NIM_API_KEY=nvapi-…
NOTION_TOKEN=secret_…          # optional
NOTION_PAGE_ID=your-page-id    # optional
LINEAR_API_KEY=lin_api_…       # optional
LINEAR_TEAM_ID=your-team-uuid  # optional
""")
                .font(.system(.caption, design: .monospaced))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 7))

                HStack(spacing: 8) {
                    Button("Copy Template") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(dotEnvTemplate, forType: .string)
                    }
                    Button("Open .env File") { openDotEnvFile() }
                    Button("Reload Now") {
                        Task {
                            nimStatus = .checking
                            notionStatus = .checking
                            linearStatus = .checking
                            await DotEnvLoader.loadAndSync()
                            await preferences.refreshSavedKeyState()
                            await checkCredentials()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .font(.subheadline)

                InfoRow("Save the file and click Reload Now, or relaunch AgentDock. Keys are stored in Keychain after first load — the .env file is only read at startup.")
            }
        }
    }

    // MARK: - Credential status

    private var credentialStatusCard: some View {
        SettingsCard(title: "Credential Status") {
            VStack(spacing: 0) {
                StatusRow(label: "NVIDIA NIM", status: nimStatus)
                Divider().padding(.leading, 16)
                StatusRow(label: "Notion", status: notionStatus)
                Divider().padding(.leading, 16)
                StatusRow(label: "Linear", status: linearStatus)
            }
        }
    }

    // MARK: - Model

    private var modelCard: some View {
        SettingsCard(title: "Model") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(NIMModel.allCases) { model in
                    Button {
                        preferences.selectedModel = model
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: preferences.selectedModel == model ? "circle.inset.filled" : "circle")
                                .foregroundStyle(preferences.selectedModel == model ? Color.accentColor : Color(nsColor: .secondaryLabelColor))
                                .font(.system(size: 14))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(model.displayName).font(.subheadline.weight(.medium))
                                Text(model.costSummary).font(.caption).foregroundStyle(Color(nsColor: .secondaryLabelColor))
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Connectors

    private var connectorsCard: some View {
        SettingsCard(title: "Connectors") {
            VStack(spacing: 0) {
                ForEach(ActionTool.allCases) { tool in
                    ConnectorRow(tool: tool, state: preferences.connectorState(for: tool))
                    if tool != ActionTool.allCases.last {
                        Divider().padding(.leading, 16)
                    }
                }
            }
        }
    }

    // MARK: - AgentDock info

    private var agentDockCard: some View {
        SettingsCard(title: "AgentDock") {
            VStack(alignment: .leading, spacing: 8) {
                InfoRow2(label: "Session analyses", value: "\(store.analyses.count)")
                InfoRow2(label: "Global hotkey", value: "Option + Space")
                Divider()
                HStack(spacing: 10) {
                    Button("Source Proofs Folder") {
                        Task {
                            let dir = await SourceArchive.shared.applicationSupportDirectory()
                            NSWorkspace.shared.open(dir)
                        }
                    }
                    Button("Log File") {
                        if let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first {
                            NSWorkspace.shared.open(base.appendingPathComponent("Logs/AgentDock"))
                        }
                    }
                }
                .font(.caption)
            }
        }
    }

    // MARK: - Helpers

    private func checkCredentials() async {
        let nim = try? await KeychainService.shared.load(.nimAPIKey)
        nimStatus = (nim?.isEmpty == false) ? .saved : .missing

        let notion = try? await KeychainService.shared.load(.notionToken)
        notionStatus = (notion?.isEmpty == false) ? .saved : .missing

        let linear = try? await KeychainService.shared.load(.linearAPIKey)
        linearStatus = (linear?.isEmpty == false) ? .saved : .missing
    }

    private func openDotEnvFile() {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let path = cwd.appendingPathComponent(".env")
        if !FileManager.default.fileExists(atPath: path.path) {
            try? dotEnvTemplate.write(to: path, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open(path)
    }

    private let dotEnvTemplate = """
NIM_API_KEY=nvapi-your-key-here
# NOTION_TOKEN=secret_your-notion-integration-token
# NOTION_PAGE_ID=your-parent-page-id-or-url
# LINEAR_API_KEY=lin_api_your-key
# LINEAR_TEAM_ID=your-team-uuid
"""
}

// MARK: - CredentialStatus

private enum CredentialStatus {
    case checking, saved, missing
}

// MARK: - Supporting views

private struct StatusRow: View {
    let label: String
    let status: CredentialStatus

    var body: some View {
        HStack(spacing: 10) {
            Text(label).font(.subheadline)
            Spacer()
            switch status {
            case .checking:
                ProgressView().controlSize(.small)
            case .saved:
                Label("Saved in Keychain", systemImage: "lock.fill")
                    .font(.caption).foregroundStyle(.green)
            case .missing:
                Label("Not set", systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(Color(nsColor: .secondaryLabelColor))
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 2)
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content
                .padding(14)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct InfoRow: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        HStack(alignment: .top, spacing: 5) {
            Image(systemName: "info.circle").font(.caption).foregroundStyle(Color(nsColor: .secondaryLabelColor))
            Text(text).font(.caption).foregroundStyle(Color(nsColor: .secondaryLabelColor)).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct InfoRow2: View {
    let label: String; let value: String
    var body: some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(Color(nsColor: .secondaryLabelColor))
            Spacer()
            Text(value).font(.subheadline.weight(.medium))
        }
    }
}

private struct ConnectorRow: View {
    let tool: ActionTool
    let state: ConnectorAuthState

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(dotColor).frame(width: 8, height: 8)
            Text(tool.rawValue).font(.subheadline)
            Spacer()
            Text(stateLabel).font(.caption).foregroundStyle(Color(nsColor: .secondaryLabelColor))
            if state == .notConnected {
                Image(systemName: "arrow.up.right.circle").font(.caption).foregroundStyle(Color(nsColor: .tertiaryLabelColor))
            }
        }
        .padding(.vertical, 8).padding(.horizontal, 2)
        .contentShape(Rectangle())
        .onTapGesture { if state == .notConnected { openPortal() } }
    }

    private var stateLabel: String {
        switch state {
        case .notConnected: "Not set — add to .env"
        case .connectedViaSystem: "Ready"
        case .connected: "Connected"
        }
    }

    private var dotColor: Color {
        switch state {
        case .notConnected: Color(nsColor: .tertiaryLabelColor)
        case .connectedViaSystem, .connected:
            switch tool {
            case .gmail: .red; case .calendar: .green; case .notion: Color(nsColor: .labelColor)
            case .linear: .purple; case .slack: .yellow; case .microsoft365: .blue
            }
        }
    }

    private func openPortal() {
        let urls: [ActionTool: String] = [
            .notion: "https://www.notion.so/my-integrations",
            .linear: "https://linear.app/settings/api",
            .slack: "https://api.slack.com/apps",
            .microsoft365: "https://portal.azure.com"
        ]
        if let s = urls[tool], let url = URL(string: s) { NSWorkspace.shared.open(url) }
    }
}
