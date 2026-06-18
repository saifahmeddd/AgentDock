import Foundation

@MainActor
final class AppPreferences: ObservableObject {
    @Published var selectedModel: OpenRouterModel {
        didSet {
            UserDefaults.standard.set(selectedModel.rawValue, forKey: Self.selectedModelKey)
        }
    }

    @Published var apiKeyDraft = ""
    @Published var apiKeyIsSaved = false
    @Published var verificationStatus: VerificationStatus = .unknown
    @Published var onboardingCompleted: Bool {
        didSet {
            UserDefaults.standard.set(onboardingCompleted, forKey: Self.onboardingCompletedKey)
        }
    }

    // Per-connector auth state, persisted in UserDefaults.
    // Connector keys are the ActionTool rawValue strings.
    @Published private var connectorStates: [String: String] = [:]

    private static let selectedModelKey = "AgentDock.selectedOpenRouterModel"
    private static let onboardingCompletedKey = "AgentDock.onboardingCompleted"
    private static let connectorStatesKey = "AgentDock.connectorStates"
    private let keychain: KeychainService
    private let openRouter: OpenRouterService

    init(keychain: KeychainService = .shared, openRouter: OpenRouterService = .shared) {
        self.keychain = keychain
        self.openRouter = openRouter

        let savedModel = UserDefaults.standard.string(forKey: Self.selectedModelKey)
        self.selectedModel = savedModel.flatMap(OpenRouterModel.init(rawValue:)) ?? .grokMini
        self.onboardingCompleted = UserDefaults.standard.bool(forKey: Self.onboardingCompletedKey)

        let saved = UserDefaults.standard.dictionary(forKey: Self.connectorStatesKey) as? [String: String] ?? [:]
        self.connectorStates = saved

        // Gmail and Calendar are always available via system APIs — no OAuth needed.
        if connectorStates[ActionTool.gmail.rawValue] == nil {
            connectorStates[ActionTool.gmail.rawValue] = ConnectorAuthState.connectedViaSystem.rawValue
        }
        if connectorStates[ActionTool.calendar.rawValue] == nil {
            connectorStates[ActionTool.calendar.rawValue] = ConnectorAuthState.connectedViaSystem.rawValue
        }

        Task {
            await refreshSavedKeyState()
        }
    }

    var maskedKeyLabel: String {
        apiKeyIsSaved ? "••••••••••••••••" : "No key saved"
    }

    // MARK: - Connector auth state

    func connectorState(for tool: ActionTool) -> ConnectorAuthState {
        guard let raw = connectorStates[tool.rawValue] else { return .notConnected }
        return ConnectorAuthState(rawValue: raw) ?? .notConnected
    }

    func setConnectorState(_ state: ConnectorAuthState, for tool: ActionTool) {
        connectorStates[tool.rawValue] = state.rawValue
        UserDefaults.standard.set(connectorStates, forKey: Self.connectorStatesKey)
    }

    // MARK: - API Key

    func refreshSavedKeyState() async {
        do {
            let key = try await keychain.loadAPIKey()
            apiKeyIsSaved = key?.isEmpty == false
        } catch {
            apiKeyIsSaved = false
            verificationStatus = .invalid(error.localizedDescription)
        }
    }

    func saveDraftKey() async {
        let trimmed = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            try await keychain.saveAPIKey(trimmed)
            apiKeyDraft = ""
            apiKeyIsSaved = true
            verificationStatus = .unknown
        } catch {
            verificationStatus = .invalid(error.localizedDescription)
        }
    }

    func loadAPIKey() async -> String? {
        do {
            return try await keychain.loadAPIKey()
        } catch {
            verificationStatus = .invalid(error.localizedDescription)
            return nil
        }
    }

    func verify() async {
        verificationStatus = .verifying

        do {
            if !apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await saveDraftKey()
            }

            guard let key = try await keychain.loadAPIKey(), !key.isEmpty else {
                verificationStatus = .invalid("Add an OpenRouter API key first.")
                return
            }

            let model = try await openRouter.verify(apiKey: key, model: selectedModel)
            verificationStatus = .valid("Verified with \(model).")
        } catch {
            verificationStatus = .invalid(error.localizedDescription)
        }
    }
}
