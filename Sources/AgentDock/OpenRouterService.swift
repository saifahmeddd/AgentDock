import Foundation

enum OpenRouterError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case emptyModelResponse
    case decodingFailed(String)
    case serverError(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Missing OpenRouter API key."
        case .invalidResponse:
            return "OpenRouter returned an invalid response."
        case .emptyModelResponse:
            return "OpenRouter returned an empty message."
        case .decodingFailed(let message):
            return "Model JSON could not be decoded: \(message)"
        case .serverError(let code, let message):
            return "OpenRouter request failed (\(code)): \(message)"
        }
    }
}

actor OpenRouterService {
    static let shared = OpenRouterService()

    private let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func verify(apiKey: String, model: OpenRouterModel) async throws -> String {
        let body = ChatRequest(
            model: model.rawValue,
            messages: [
                ChatMessage(role: "system", content: "Reply with JSON only."),
                ChatMessage(role: "user", content: #"{"ok":true}"#)
            ],
            temperature: 0,
            maxTokens: 20,
            responseFormat: ResponseFormat(type: "json_object")
        )

        let response: ChatResponse = try await send(body: body, apiKey: apiKey)
        return response.model ?? model.rawValue
    }

    func analyze(item: IntakeItem, apiKey: String, selectedModel: OpenRouterModel) async throws -> AgentAnalysis {
        let modelAttempts = [selectedModel, selectedModel, selectedModel == .fallback ? selectedModel : .fallback]
        var lastError: Error?

        for attempt in 0..<modelAttempts.count {
            let model = modelAttempts[attempt]
            do {
                return try await analyzeOnce(item: item, apiKey: apiKey, model: model, usedFallback: model != selectedModel)
            } catch {
                lastError = error
                if attempt < modelAttempts.count - 1 {
                    let backoff = UInt64(pow(2.0, Double(attempt))) * 400_000_000
                    try? await Task.sleep(nanoseconds: backoff)
                }
            }
        }

        throw lastError ?? OpenRouterError.invalidResponse
    }

    private func analyzeOnce(
        item: IntakeItem,
        apiKey: String,
        model: OpenRouterModel,
        usedFallback: Bool
    ) async throws -> AgentAnalysis {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenRouterError.missingAPIKey
        }

        let body = ChatRequest(
            model: model.rawValue,
            messages: [
                ChatMessage(role: "system", content: Self.systemPrompt),
                ChatMessage(role: "user", content: userPrompt(for: item))
            ],
            temperature: 0.1,
            maxTokens: 1200,
            responseFormat: ResponseFormat(type: "json_object")
        )

        let response: ChatResponse = try await send(body: body, apiKey: apiKey)
        guard let content = response.choices.first?.message.content, !content.isEmpty else {
            throw OpenRouterError.emptyModelResponse
        }

        let structured = try decodeStructuredResponse(content)
        return analysis(from: structured, item: item, model: model, response: response, usedFallback: usedFallback)
    }

    private func send<T: Decodable>(body: ChatRequest, apiKey: String) async throws -> T {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("agentdock-mac", forHTTPHeaderField: "HTTP-Referer")
        request.addValue("AgentDock", forHTTPHeaderField: "X-Title")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenRouterError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "No error body"
            throw OpenRouterError.serverError(http.statusCode, message)
        }

        return try JSONDecoder().decode(T.self, from: data)
    }

    private func decodeStructuredResponse(_ content: String) throws -> StructuredAIResponse {
        let cleaned = content
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8) else {
            throw OpenRouterError.decodingFailed("Content was not UTF-8.")
        }

        do {
            return try JSONDecoder().decode(StructuredAIResponse.self, from: data)
        } catch {
            throw OpenRouterError.decodingFailed(error.localizedDescription)
        }
    }

    private func analysis(
        from response: StructuredAIResponse,
        item: IntakeItem,
        model: OpenRouterModel,
        response chatResponse: ChatResponse,
        usedFallback: Bool
    ) -> AgentAnalysis {
        let commitments = response.commitments.map {
            CommitmentDraft(
                title: $0.title,
                owner: $0.owner ?? "You",
                priority: Priority(rawValue: $0.priority ?? "") ?? .normal,
                deadline: $0.deadline,
                reminder: $0.reminder ?? ($0.deadline.map { "Remind before \($0)" } ?? "Remind tomorrow at 9:00 AM"),
                sourceProof: $0.sourceProof ?? response.sourceProof ?? item.body
            )
        }

        let followUps = response.followUps.map {
            FollowUpDraft(
                title: $0.title,
                responsibleParty: $0.responsibleParty ?? "Other person",
                checkBack: $0.checkBack ?? "Check back in 2 business days",
                sourceProof: $0.sourceProof ?? response.sourceProof ?? item.body
            )
        }

        let actions = response.proposedActions.map {
            ProposedAction(
                title: $0.title,
                tool: ActionTool(rawValue: $0.tool ?? "") ?? .gmail,
                approvalPrompt: $0.approvalPrompt ?? $0.description,
                sourceProof: $0.sourceProof ?? response.sourceProof ?? item.body,
                details: $0.description,
                target: $0.target
            )
        }

        let inputTokens = chatResponse.usage?.promptTokens
        let outputTokens = chatResponse.usage?.completionTokens
        let cost = estimateCost(model: model, inputTokens: inputTokens, outputTokens: outputTokens)

        return AgentAnalysis(
            intake: item,
            classification: WorkClassification(rawValue: response.classification) ?? inferredClassification(commitments: commitments, followUps: followUps, actions: actions),
            commitments: commitments,
            followUps: followUps,
            proposedActions: actions,
            evidence: response.evidence.map { EvidenceItem(label: $0.label, value: $0.value) },
            notes: [
                AgentNote(agentName: "Extractor", summary: "Structured messy source text into clean work objects.", symbolName: "brain"),
                AgentNote(agentName: "Tracker", summary: "Detected \(commitments.count) commitments and \(followUps.count) waiting items.", symbolName: "checklist"),
                AgentNote(agentName: "Executor", summary: actions.isEmpty ? "No tool action proposed." : "Prepared \(actions.count) approval-gated actions.", symbolName: "bolt")
            ],
            modelID: chatResponse.model ?? model.rawValue,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            estimatedCost: cost,
            usedFallback: usedFallback,
            executionLogs: [],
            activeAgents: []
        )
    }

    private func estimateCost(model: OpenRouterModel, inputTokens: Int?, outputTokens: Int?) -> Decimal? {
        guard let inputTokens, let outputTokens else { return nil }
        let input = Decimal(inputTokens) * model.inputPricePerMillionTokens / Decimal(1_000_000)
        let output = Decimal(outputTokens) * model.outputPricePerMillionTokens / Decimal(1_000_000)
        return input + output
    }

    private func inferredClassification(
        commitments: [CommitmentDraft],
        followUps: [FollowUpDraft],
        actions: [ProposedAction]
    ) -> WorkClassification {
        if !actions.isEmpty { return .aiAction }
        if !followUps.isEmpty { return .waitingItem }
        if !commitments.isEmpty { return .humanTask }
        return .referenceOnly
    }

    private func userPrompt(for item: IntakeItem) -> String {
        """
        Analyze this AgentDock intake.

        Source type: \(item.sourceKind.rawValue)
        Original source: \(item.originalSource)
        Metadata: \(item.metadata)

        Raw input:
        \(item.body)
        """
    }

    private static let systemPrompt = """
    You are AgentDock's work-intake agent squad. Extract commitments, waiting/follow-up items, approval-gated AI actions, deadlines, source proof, and evidence from messy work.

    Return JSON only with this exact schema:
    {
      "classification": "Human task | Waiting item | AI-doable action | Reference only",
      "source_proof": "short quote from source",
      "commitments": [
        {
          "title": "clean task title",
          "owner": "You | Team | named owner",
          "priority": "Low | Normal | High | Urgent",
          "deadline": "natural-language deadline or null",
          "reminder": "natural-language reminder",
          "source_proof": "quote"
        }
      ],
      "follow_ups": [
        {
          "title": "clean waiting item",
          "responsible_party": "person/team",
          "check_back": "when to check back",
          "source_proof": "quote"
        }
      ],
      "proposed_actions": [
        {
          "title": "short action",
          "tool": "Gmail | Calendar | Notion | Linear | Slack | Microsoft 365",
          "description": "clear description of what will happen",
          "target": "email/person/date/url if available",
          "approval_prompt": "what user must approve",
          "source_proof": "quote"
        }
      ],
      "evidence": [
        { "label": "Original source", "value": "..." }
      ]
    }

    Do not execute actions. If uncertain, preserve source proof and choose the safest interpretation.
    """
}

private struct ChatRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double
    let maxTokens: Int
    let responseFormat: ResponseFormat

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxTokens = "max_tokens"
        case responseFormat = "response_format"
    }
}

private struct ChatMessage: Codable {
    let role: String
    let content: String
}

private struct ResponseFormat: Encodable {
    let type: String
}

private struct ChatResponse: Decodable {
    let choices: [Choice]
    let model: String?
    let usage: Usage?
}

private struct Choice: Decodable {
    let message: ChatMessage
}

private struct Usage: Decodable {
    let promptTokens: Int?
    let completionTokens: Int?

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
    }
}

private struct StructuredAIResponse: Decodable {
    let classification: String
    let sourceProof: String?
    let commitments: [StructuredCommitment]
    let followUps: [StructuredFollowUp]
    let proposedActions: [StructuredAction]
    let evidence: [StructuredEvidence]

    enum CodingKeys: String, CodingKey {
        case classification
        case sourceProof = "source_proof"
        case commitments
        case followUps = "follow_ups"
        case proposedActions = "proposed_actions"
        case evidence
    }
}

private struct StructuredCommitment: Decodable {
    let title: String
    let owner: String?
    let priority: String?
    let deadline: String?
    let reminder: String?
    let sourceProof: String?

    enum CodingKeys: String, CodingKey {
        case title
        case owner
        case priority
        case deadline
        case reminder
        case sourceProof = "source_proof"
    }
}

private struct StructuredFollowUp: Decodable {
    let title: String
    let responsibleParty: String?
    let checkBack: String?
    let sourceProof: String?

    enum CodingKeys: String, CodingKey {
        case title
        case responsibleParty = "responsible_party"
        case checkBack = "check_back"
        case sourceProof = "source_proof"
    }
}

private struct StructuredAction: Decodable {
    let title: String
    let tool: String?
    let description: String
    let target: String?
    let approvalPrompt: String?
    let sourceProof: String?

    enum CodingKeys: String, CodingKey {
        case title
        case tool
        case description
        case target
        case approvalPrompt = "approval_prompt"
        case sourceProof = "source_proof"
    }
}

private struct StructuredEvidence: Decodable {
    let label: String
    let value: String
}
