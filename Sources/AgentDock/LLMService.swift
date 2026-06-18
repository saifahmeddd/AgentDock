import Foundation

// MARK: - Errors

enum LLMError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case emptyModelResponse
    case decodingFailed(String)
    case serverError(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Missing NVIDIA NIM API key. Add it in Settings."
        case .invalidResponse:
            return "The AI service returned an invalid response."
        case .emptyModelResponse:
            return "The AI service returned an empty message."
        case .decodingFailed(let message):
            return "Could not parse AI response: \(message)"
        case .serverError(let code, let message):
            return "AI request failed (\(code)): \(message)"
        }
    }
}

// MARK: - LLMService (NVIDIA NIM)

actor LLMService {
    static let shared = LLMService()

    private let endpoint = URL(string: "https://integrate.api.nvidia.com/v1/chat/completions")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func verify(apiKey: String, model: NIMModel) async throws -> String {
        let body = ChatRequest(
            model: model.rawValue,
            messages: [
                ChatMessage(role: "system", content: "Reply with valid JSON only."),
                ChatMessage(role: "user", content: "{\"ok\":true}")
            ],
            temperature: 0,
            maxTokens: 20
        )
        let response: ChatResponse = try await send(body: body, apiKey: apiKey)
        return response.model ?? model.rawValue
    }

    func analyze(item: IntakeItem, apiKey: String, selectedModel: NIMModel) async throws -> AgentAnalysis {
        let attempts: [NIMModel] = [selectedModel, selectedModel, selectedModel == .fallback ? selectedModel : .fallback]
        var lastError: Error?

        for (attempt, model) in attempts.enumerated() {
            do {
                return try await analyzeOnce(item: item, apiKey: apiKey, model: model, usedFallback: model != selectedModel)
            } catch {
                lastError = error
                if attempt < attempts.count - 1 {
                    let backoff = UInt64(pow(2.0, Double(attempt))) * 400_000_000
                    try? await Task.sleep(nanoseconds: backoff)
                }
            }
        }

        throw lastError ?? LLMError.invalidResponse
    }

    private func analyzeOnce(item: IntakeItem, apiKey: String, model: NIMModel, usedFallback: Bool) async throws -> AgentAnalysis {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMError.missingAPIKey
        }

        let body = ChatRequest(
            model: model.rawValue,
            messages: [
                ChatMessage(role: "system", content: Self.systemPrompt),
                ChatMessage(role: "user", content: userPrompt(for: item))
            ],
            temperature: 0.1,
            maxTokens: 1400
        )

        let response: ChatResponse = try await send(body: body, apiKey: apiKey)
        guard let content = response.choices.first?.message.content, !content.isEmpty else {
            throw LLMError.emptyModelResponse
        }

        let structured = try decodeStructuredResponse(content)
        return makeAnalysis(from: structured, item: item, model: model, response: response, usedFallback: usedFallback)
    }

    private func send<T: Decodable>(body: ChatRequest, apiKey: String) async throws -> T {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("AgentDock", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw LLMError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "No error body"
            throw LLMError.serverError(http.statusCode, message)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func decodeStructuredResponse(_ content: String) throws -> StructuredAIResponse {
        var cleaned = content
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !cleaned.hasPrefix("{"),
           let start = cleaned.firstIndex(of: "{"),
           let end = cleaned.lastIndex(of: "}") {
            cleaned = String(cleaned[start...end])
        }

        guard let data = cleaned.data(using: .utf8) else {
            throw LLMError.decodingFailed("Response was not valid UTF-8.")
        }

        do {
            return try JSONDecoder().decode(StructuredAIResponse.self, from: data)
        } catch {
            throw LLMError.decodingFailed(error.localizedDescription)
        }
    }

    private func makeAnalysis(from structured: StructuredAIResponse, item: IntakeItem, model: NIMModel, response: ChatResponse, usedFallback: Bool) -> AgentAnalysis {
        let commitments = structured.commitments.map {
            CommitmentDraft(
                title: $0.title,
                owner: $0.owner ?? "You",
                priority: Priority(rawValue: $0.priority ?? "") ?? .normal,
                deadline: $0.deadline,
                reminder: $0.reminder ?? ($0.deadline.map { "Remind before \($0)" } ?? "Remind tomorrow at 9 AM"),
                sourceProof: $0.sourceProof ?? structured.sourceProof ?? item.body
            )
        }
        let followUps = structured.followUps.map {
            FollowUpDraft(
                title: $0.title,
                responsibleParty: $0.responsibleParty ?? "Other person",
                checkBack: $0.checkBack ?? "Check back in 2 business days",
                sourceProof: $0.sourceProof ?? structured.sourceProof ?? item.body
            )
        }
        let actions = structured.proposedActions.map {
            ProposedAction(
                title: $0.title,
                tool: ActionTool(rawValue: $0.tool ?? "") ?? .gmail,
                approvalPrompt: $0.approvalPrompt ?? $0.description,
                sourceProof: $0.sourceProof ?? structured.sourceProof ?? item.body,
                details: $0.description,
                target: $0.target
            )
        }

        let inputTokens = response.usage?.promptTokens
        let outputTokens = response.usage?.completionTokens
        let cost = estimateCost(model: model, inputTokens: inputTokens, outputTokens: outputTokens)
        let classification = WorkClassification(rawValue: structured.classification)
            ?? inferClassification(commitments: commitments, followUps: followUps, actions: actions)

        return AgentAnalysis(
            intake: item,
            classification: classification,
            commitments: commitments,
            followUps: followUps,
            proposedActions: actions,
            evidence: structured.evidence.map { EvidenceItem(label: $0.label, value: $0.value) },
            notes: [
                AgentNote(agentName: "Extractor", summary: "Structured source text using \(model.displayName).", symbolName: "brain"),
                AgentNote(agentName: "Tracker", summary: "Found \(commitments.count) commitment(s) and \(followUps.count) follow-up(s).", symbolName: "checklist"),
                AgentNote(agentName: "Executor", summary: actions.isEmpty ? "No tool action proposed." : "\(actions.count) action(s) queued for approval.", symbolName: "bolt")
            ],
            modelID: response.model ?? model.rawValue,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            estimatedCost: cost,
            usedFallback: usedFallback,
            executionLogs: []
        )
    }

    private func estimateCost(model: NIMModel, inputTokens: Int?, outputTokens: Int?) -> Decimal? {
        guard let inputTokens, let outputTokens else { return nil }
        let input = Decimal(inputTokens) * model.inputPricePerMillionTokens / Decimal(1_000_000)
        let output = Decimal(outputTokens) * model.outputPricePerMillionTokens / Decimal(1_000_000)
        return input + output
    }

    private func inferClassification(commitments: [CommitmentDraft], followUps: [FollowUpDraft], actions: [ProposedAction]) -> WorkClassification {
        if !actions.isEmpty { return .aiAction }
        if !followUps.isEmpty { return .waitingItem }
        if !commitments.isEmpty { return .humanTask }
        return .referenceOnly
    }

    private func userPrompt(for item: IntakeItem) -> String {
        "Source type: \(item.sourceKind.rawValue)\nOriginal source: \(item.originalSource)\n\nRaw input:\n\(item.body)"
    }

    private static let systemPrompt = """
    You are AgentDock, a work-intake AI. Extract structured, actionable items from messy work inputs.

    Return ONLY valid JSON — no prose, no markdown fences:
    {
      "classification": "Human task | Waiting item | AI-doable action | Reference only",
      "source_proof": "short exact quote from the input",
      "commitments": [{"title":"","owner":"You","priority":"Low|Normal|High|Urgent","deadline":null,"reminder":"","source_proof":""}],
      "follow_ups": [{"title":"","responsible_party":"","check_back":"","source_proof":""}],
      "proposed_actions": [{"title":"","tool":"Gmail|Calendar|Notion|Linear|Slack|Microsoft 365","description":"","target":null,"approval_prompt":"","source_proof":""}],
      "evidence": [{"label":"","value":""}]
    }
    Rules: never auto-execute. If uncertain, preserve source proof. Return ONLY the JSON object.
    """
}

// MARK: - Private decodable types

private struct ChatRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double
    let maxTokens: Int
    enum CodingKeys: String, CodingKey {
        case model, messages, temperature
        case maxTokens = "max_tokens"
    }
}
private struct ChatMessage: Codable { let role: String; let content: String }
private struct ChatResponse: Decodable { let choices: [Choice]; let model: String?; let usage: Usage? }
private struct Choice: Decodable { let message: ChatMessage }
private struct Usage: Decodable {
    let promptTokens: Int?; let completionTokens: Int?
    enum CodingKeys: String, CodingKey { case promptTokens = "prompt_tokens"; case completionTokens = "completion_tokens" }
}
private struct StructuredAIResponse: Decodable {
    let classification: String; let sourceProof: String?
    let commitments: [StructuredCommitment]; let followUps: [StructuredFollowUp]
    let proposedActions: [StructuredAction]; let evidence: [StructuredEvidence]
    enum CodingKeys: String, CodingKey {
        case classification; case sourceProof = "source_proof"; case commitments
        case followUps = "follow_ups"; case proposedActions = "proposed_actions"; case evidence
    }
}
private struct StructuredCommitment: Decodable {
    let title: String; let owner: String?; let priority: String?; let deadline: String?; let reminder: String?; let sourceProof: String?
    enum CodingKeys: String, CodingKey { case title, owner, priority, deadline, reminder; case sourceProof = "source_proof" }
}
private struct StructuredFollowUp: Decodable {
    let title: String; let responsibleParty: String?; let checkBack: String?; let sourceProof: String?
    enum CodingKeys: String, CodingKey { case title; case responsibleParty = "responsible_party"; case checkBack = "check_back"; case sourceProof = "source_proof" }
}
private struct StructuredAction: Decodable {
    let title: String; let tool: String?; let description: String; let target: String?; let approvalPrompt: String?; let sourceProof: String?
    enum CodingKeys: String, CodingKey { case title, tool, description, target; case approvalPrompt = "approval_prompt"; case sourceProof = "source_proof" }
}
private struct StructuredEvidence: Decodable { let label: String; let value: String }
