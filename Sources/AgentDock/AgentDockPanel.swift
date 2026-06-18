import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct AgentDockPanel: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var store: AgentDockStore
    @EnvironmentObject private var preferences: AppPreferences
    @State private var isDropTargeted = false
    @State private var shimmerOffset = -180.0

    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HeaderView()

                if store.hotkeyPermissionMissing {
                    HotkeyPermissionBanner()
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                ScrollView {
                    VStack(spacing: 14) {
                        AgentSquadView(activeAgents: store.activeAgents)

                        if let badge = store.sourceDetectionBadge {
                            SourceBadgeView(text: badge)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        DropZoneView(isTargeted: isDropTargeted, shimmerOffset: shimmerOffset)
                            .onDrop(
                                of: [
                                    UTType.fileURL.identifier,
                                    UTType.url.identifier,
                                    UTType.text.identifier,
                                    UTType.plainText.identifier
                                ],
                                isTargeted: $isDropTargeted,
                                perform: handleDrop
                            )
                            .onChange(of: isDropTargeted) { _, newValue in
                                guard newValue, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
                                shimmerOffset = -180
                                withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                                    shimmerOffset = 180
                                }
                            }

                        ComposerView()

                        ConnectorPillRow()

                        if store.isProcessing {
                            ProcessingView()
                                .transition(.opacity)
                        } else if let analysis = store.selectedAnalysis {
                            AnalysisDetailView(analysis: analysis)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .opacity
                                ))
                        } else {
                            EmptyStateView()
                        }
                    }
                    .padding(14)
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(width: 380, height: 580)
        .onAppear {
            store.attachModelContext(modelContext)
        }
        .sheet(isPresented: $store.showingOnboarding) {
            OnboardingView()
                .environmentObject(preferences)
                .frame(width: 420, height: 360)
        }
        .sheet(item: $store.editingAction) { action in
            ActionEditSheet(action: action)
                .environmentObject(store)
                .frame(width: 440, height: 360)
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: store.selectedAnalysisID)
        .animation(.spring(response: 0.28, dampingFraction: 0.9), value: store.sourceDetectionBadge)
        .animation(.spring(response: 0.28, dampingFraction: 0.9), value: store.hotkeyPermissionMissing)
        .animation(.spring(response: 0.28, dampingFraction: 0.9), value: store.isProcessing)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handled = true
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    let url = urlFromProviderItem(item)
                    Task { @MainActor in
                        if let url { store.ingestFiles([url]) }
                    }
                }
                continue
            }

            if provider.canLoadObject(ofClass: NSString.self) {
                handled = true
                provider.loadObject(ofClass: NSString.self) { object, _ in
                    let text = object as? String
                    Task { @MainActor in
                        if let text { store.ingestDroppedText(text) }
                    }
                }
            }
        }

        return handled
    }

    private func urlFromProviderItem(_ item: NSSecureCoding?) -> URL? {
        if let url = item as? URL { return url }
        if let data = item as? Data { return URL(dataRepresentation: data, relativeTo: nil) }
        if let string = item as? String { return URL(string: string) }
        return nil
    }
}

// MARK: - HeaderView

private struct HeaderView: View {
    @EnvironmentObject private var store: AgentDockStore

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color(nsColor: .controlAccentColor))
                .frame(width: 34, height: 34)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text("AgentDock")
                    .font(.headline)
                    .foregroundStyle(Color(nsColor: .labelColor))
                Text(store.analyses.isEmpty ? "Drop work. Agents handle it." : "\(store.analyses.count) analysis\(store.analyses.count == 1 ? "" : "es")")
                    .font(.caption)
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .contentTransition(.numericText())
                    .animation(.default, value: store.analyses.count)
            }

            Spacer()

            if store.isProcessing {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                store.clearAll()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Clear all analyses")
            .disabled(store.analyses.isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

// MARK: - HotkeyPermissionBanner

private struct HotkeyPermissionBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "keyboard.badge.exclamationmark")
                .foregroundStyle(.orange)
            Text("Option+Space requires Accessibility permission.")
                .font(.caption)
                .foregroundStyle(Color(nsColor: .labelColor))
            Spacer()
            Button("Open Settings") {
                NSWorkspace.shared.open(
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                )
            }
            .font(.caption)
            .buttonStyle(.borderless)
            .foregroundStyle(Color(nsColor: .controlAccentColor))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.1))
    }
}

// MARK: - AgentSquadView

private struct AgentSquadView: View {
    let activeAgents: Set<AgentRole>

    var body: some View {
        HStack(spacing: 10) {
            ForEach(AgentRole.allCases) { agent in
                VStack(spacing: 5) {
                    Image(systemName: agent.symbolName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(
                            activeAgents.contains(agent)
                                ? Color(nsColor: .controlAccentColor)
                                : Color(nsColor: .tertiaryLabelColor)
                        )
                        .frame(width: 38, height: 38)
                        .background(
                            activeAgents.contains(agent)
                                ? AnyShapeStyle(.thinMaterial)
                                : AnyShapeStyle(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                            , in: Circle()
                        )
                        .opacity(activeAgents.contains(agent) && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.55 : 1)
                        .animation(
                            activeAgents.contains(agent) && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                                ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true)
                                : .default,
                            value: activeAgents
                        )
                    Text(agent.rawValue)
                        .font(.caption2)
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                }
                .frame(width: 58)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - ComposerView

private struct ComposerView: View {
    @EnvironmentObject private var store: AgentDockStore

    var body: some View {
        VStack(spacing: 9) {
            HStack(spacing: 8) {
                Picker("Source", selection: $store.selectedSource) {
                    ForEach(IntakeSourceKind.allCases.filter { $0 != .unknown }) { source in
                        Label(source.rawValue, systemImage: source.symbolName)
                            .tag(source)
                    }
                }
                .labelsHidden()

                Button {
                    store.ingestDraftText()
                } label: {
                    Label("Analyze", systemImage: "wand.and.stars")
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isProcessing)
            }

            TextEditor(text: $store.draftText)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(height: 82)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
                )
        }
    }
}

// MARK: - ProcessingView

private struct ProcessingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("Analyzing…")
                .font(.subheadline)
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

// MARK: - EmptyStateView

private struct EmptyStateView: View {
    @State private var arrowOffset = -4.0

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Color(nsColor: .controlAccentColor))
                .offset(y: arrowOffset)
                .onAppear {
                    guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
                    withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                        arrowOffset = 4
                    }
                }

            Text("Drop work here")
                .font(.headline)
                .foregroundStyle(Color(nsColor: .labelColor))

            Text("Slack, Gmail, PDFs, screenshots, browser links, and copied text.")
                .font(.caption)
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

// MARK: - DropZoneView

private struct DropZoneView: View {
    let isTargeted: Bool
    let shimmerOffset: Double

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: isTargeted ? "arrow.down.doc.fill" : "arrow.down.doc")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(isTargeted ? Color(nsColor: .selectedControlTextColor) : Color(nsColor: .controlAccentColor))

            Text(isTargeted ? "Release to analyze" : "Drop work here")
                .font(.headline)
                .foregroundStyle(isTargeted ? Color(nsColor: .selectedControlTextColor) : Color(nsColor: .labelColor))

            HStack(spacing: 6) {
                DropTypePill(symbol: "envelope", text: "Mail")
                DropTypePill(symbol: "doc", text: "Docs")
                DropTypePill(symbol: "link", text: "Links")
                DropTypePill(symbol: "photo", text: "Images")
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 126)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isTargeted
                          ? Color(nsColor: .controlAccentColor).opacity(0.92)
                          : Color(nsColor: .controlBackgroundColor).opacity(0.58))
                if isTargeted {
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.28), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(width: 76)
                    .rotationEffect(.degrees(22))
                    .offset(x: shimmerOffset)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    Color(nsColor: isTargeted ? .controlAccentColor : .separatorColor),
                    style: StrokeStyle(lineWidth: 1.4, dash: isTargeted ? [] : [7, 5])
                )
        )
    }
}

private struct DropTypePill: View {
    let symbol: String
    let text: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: Capsule())
    }
}

// MARK: - SourceBadgeView

private struct SourceBadgeView: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "checkmark.seal.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color(nsColor: .labelColor))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.regularMaterial, in: Capsule())
    }
}

// MARK: - ConnectorPillRow

private struct ConnectorPillRow: View {
    @EnvironmentObject private var preferences: AppPreferences

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 7) {
                ForEach(ActionTool.allCases) { tool in
                    let state = preferences.connectorState(for: tool)
                    HStack(spacing: 5) {
                        Circle()
                            .fill(indicatorColor(for: tool, state: state))
                            .frame(width: 7, height: 7)
                        Text(tool.rawValue)
                        Text(stateLabel(state))
                            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    }
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.thinMaterial, in: Capsule())
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func stateLabel(_ state: ConnectorAuthState) -> String {
        switch state {
        case .notConnected: "Connect"
        case .connectedViaSystem: "Ready"
        case .connected: "Connected"
        }
    }

    private func indicatorColor(for tool: ActionTool, state: ConnectorAuthState) -> Color {
        guard state != .notConnected else { return Color(nsColor: .tertiaryLabelColor) }
        switch tool {
        case .gmail: return .red
        case .calendar: return .green
        case .notion: return Color(nsColor: .labelColor)
        case .linear: return .purple
        case .slack: return .blue
        case .microsoft365: return .orange
        }
    }
}

// MARK: - OnboardingView

private struct OnboardingView: View {
    @EnvironmentObject private var preferences: AppPreferences
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0

    private let symbols = ["square.stack.3d.up", "key.fill", "tray.and.arrow.down"]
    private let titles = ["Welcome to AgentDock", "Add OpenRouter", "Drop something to try it"]
    private let bodies = [
        "A native menu bar AI action layer for messy work — Slack, Gmail, PDFs, and more.",
        "Paste your API key in Settings. It is stored securely in macOS Keychain.",
        "Drop text, screenshots, PDFs, browser links, or files into the panel."
    ]

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: symbols[step])
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(Color(nsColor: .controlAccentColor))

            Text(titles[step])
                .font(.title2.weight(.semibold))

            Text(bodies[step])
                .font(.body)
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 34)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            HStack {
                Button("Skip") {
                    preferences.onboardingCompleted = true
                    dismiss()
                }
                Spacer()

                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(i == step ? Color(nsColor: .controlAccentColor) : Color(nsColor: .tertiaryLabelColor))
                            .frame(width: 6, height: 6)
                    }
                }

                Spacer()

                Button(step == 2 ? "Done" : "Next") {
                    if step == 2 {
                        preferences.onboardingCompleted = true
                        dismiss()
                    } else {
                        withAnimation { step += 1 }
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(20)
        }
    }
}

// MARK: - ActionEditSheet

private struct ActionEditSheet: View {
    @EnvironmentObject private var store: AgentDockStore
    @Environment(\.dismiss) private var dismiss
    let action: ProposedAction
    @State private var editedDetails: String

    init(action: ProposedAction) {
        self.action = action
        _editedDetails = State(initialValue: action.details.isEmpty ? action.approvalPrompt : action.details)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Edit Action")
                    .font(.headline)
                Text(action.title)
                    .font(.subheadline)
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            }

            TextEditor(text: $editedDetails)
                .font(.body)
                .frame(height: 210)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )

            Text("This will be sent to \(action.tool.rawValue). Review carefully before approving.")
                .font(.caption)
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Approve & Run") {
                    var edited = action
                    edited.details = editedDetails
                    store.approve(edited)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
        }
        .padding(18)
    }
}

// MARK: - VisualEffectView

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
