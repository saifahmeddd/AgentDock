import Foundation
import SwiftData

// MARK: - Enums

enum IntakeSourceKind: String, CaseIterable, Identifiable, Codable {
    case slack = "Slack"
    case whatsapp = "WhatsApp"
    case gmail = "Gmail"
    case teams = "Teams"
    case pdf = "PDF"
    case screenshot = "Screenshot"
    case browser = "Browser"
    case clipboard = "Clipboard"
    case file = "File"
    case unknown = "Unknown"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .slack: "bubble.left.and.bubble.right"
        case .whatsapp: "message"
        case .gmail: "envelope"
        case .teams: "person.3"
        case .pdf: "doc.richtext"
        case .screenshot: "camera.viewfinder"
        case .browser: "safari"
        case .clipboard: "clipboard"
        case .file: "doc"
        case .unknown: "questionmark.circle"
        }
    }
}

enum Priority: String, CaseIterable, Identifiable, Codable {
    case low = "Low"
    case normal = "Normal"
    case high = "High"
    case urgent = "Urgent"

    var id: String { rawValue }
}

enum ActionTool: String, CaseIterable, Identifiable, Codable {
    case gmail = "Gmail"
    case calendar = "Calendar"
    case notion = "Notion"
    case linear = "Linear"
    case slack = "Slack"
    case microsoft365 = "Microsoft 365"

    var id: String { rawValue }
}

enum WorkClassification: String, Codable {
    case humanTask = "Human task"
    case waitingItem = "Waiting item"
    case aiAction = "AI-doable action"
    case referenceOnly = "Reference only"
}

enum AgentRole: String, CaseIterable, Identifiable, Codable {
    case extractor = "Extractor"
    case tracker = "Tracker"
    case scheduler = "Scheduler"
    case proofer = "Proofer"
    case executor = "Executor"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .extractor: "brain"
        case .tracker: "doc.text.magnifyingglass"
        case .scheduler: "checklist"
        case .proofer: "clock"
        case .executor: "bolt"
        }
    }
}

enum NIMModel: String, CaseIterable, Identifiable, Codable {
    case llama8b = "meta/llama-3.1-8b-instruct"
    case llama70b = "meta/llama-3.3-70b-instruct"
    case mistral7b = "mistralai/mistral-7b-instruct-v0.3"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .llama8b: "Llama 3.1 8B"
        case .llama70b: "Llama 3.3 70B"
        case .mistral7b: "Mistral 7B"
        }
    }

    var latencyLabel: String {
        switch self {
        case .llama8b: "Fast"
        case .llama70b: "Moderate"
        case .mistral7b: "Fast"
        }
    }

    // NVIDIA NIM free tier — $0 usage
    var inputPricePerMillionTokens: Decimal { 0 }
    var outputPricePerMillionTokens: Decimal { 0 }

    var costSummary: String {
        switch self {
        case .llama8b: "Free · Fast (default)"
        case .llama70b: "Free · Higher quality"
        case .mistral7b: "Free · Fastest"
        }
    }

    static let fallback: NIMModel = .llama8b
}

enum VerificationStatus: Equatable {
    case unknown
    case verifying
    case valid(String)
    case invalid(String)
}

// MARK: - In-Memory Structs (Codable for persistence)

struct IntakeItem: Identifiable, Equatable, Codable {
    let id: UUID
    let createdAt: Date
    var title: String
    var body: String
    var sourceKind: IntakeSourceKind
    var originalSource: String
    var attachments: [URL]
    var sourceBadge: String?
    var metadata: [String: String]

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        title: String,
        body: String,
        sourceKind: IntakeSourceKind,
        originalSource: String,
        attachments: [URL] = [],
        sourceBadge: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.title = title
        self.body = body
        self.sourceKind = sourceKind
        self.originalSource = originalSource
        self.attachments = attachments
        self.sourceBadge = sourceBadge
        self.metadata = metadata
    }
}

struct AgentAnalysis: Identifiable, Codable {
    let id: UUID
    let intake: IntakeItem
    var classification: WorkClassification
    var commitments: [CommitmentDraft]
    var followUps: [FollowUpDraft]
    var proposedActions: [ProposedAction]
    var evidence: [EvidenceItem]
    var notes: [AgentNote]
    var modelID: String?
    var inputTokens: Int?
    var outputTokens: Int?
    var estimatedCostString: String?
    var usedFallback: Bool
    var executionLogs: [ExecutionLog]
    var activeAgents: [AgentRole]

    init(
        id: UUID = UUID(),
        intake: IntakeItem,
        classification: WorkClassification,
        commitments: [CommitmentDraft],
        followUps: [FollowUpDraft],
        proposedActions: [ProposedAction],
        evidence: [EvidenceItem],
        notes: [AgentNote],
        modelID: String? = nil,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        estimatedCost: Decimal? = nil,
        usedFallback: Bool,
        executionLogs: [ExecutionLog],
        activeAgents: Set<AgentRole> = []
    ) {
        self.id = id
        self.intake = intake
        self.classification = classification
        self.commitments = commitments
        self.followUps = followUps
        self.proposedActions = proposedActions
        self.evidence = evidence
        self.notes = notes
        self.modelID = modelID
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.estimatedCostString = estimatedCost.map { NSDecimalNumber(decimal: $0).stringValue }
        self.usedFallback = usedFallback
        self.executionLogs = executionLogs
        self.activeAgents = Array(activeAgents)
    }

    var estimatedCost: Decimal? {
        estimatedCostString.flatMap { Decimal(string: $0) }
    }

    var costLabel: String {
        guard let estimatedCostString else { return "Local analysis" }
        return "$\(estimatedCostString)"
    }
}

struct CommitmentDraft: Identifiable, Codable {
    let id: UUID
    var title: String
    var owner: String
    var priority: Priority
    var deadline: String?
    var reminder: String
    var sourceProof: String
    var isDone: Bool

    init(
        id: UUID = UUID(),
        title: String,
        owner: String,
        priority: Priority,
        deadline: String?,
        reminder: String,
        sourceProof: String,
        isDone: Bool = false
    ) {
        self.id = id
        self.title = title
        self.owner = owner
        self.priority = priority
        self.deadline = deadline
        self.reminder = reminder
        self.sourceProof = sourceProof
        self.isDone = isDone
    }
}

struct FollowUpDraft: Identifiable, Codable {
    let id: UUID
    var title: String
    var responsibleParty: String
    var checkBack: String
    var sourceProof: String
    var isDone: Bool

    init(
        id: UUID = UUID(),
        title: String,
        responsibleParty: String,
        checkBack: String,
        sourceProof: String,
        isDone: Bool = false
    ) {
        self.id = id
        self.title = title
        self.responsibleParty = responsibleParty
        self.checkBack = checkBack
        self.sourceProof = sourceProof
        self.isDone = isDone
    }
}

struct ProposedAction: Identifiable, Codable {
    let id: UUID
    var title: String
    var tool: ActionTool
    var approvalPrompt: String
    var sourceProof: String
    var details: String
    var target: String?

    init(
        id: UUID = UUID(),
        title: String,
        tool: ActionTool,
        approvalPrompt: String,
        sourceProof: String,
        details: String = "",
        target: String? = nil
    ) {
        self.id = id
        self.title = title
        self.tool = tool
        self.approvalPrompt = approvalPrompt
        self.sourceProof = sourceProof
        self.details = details
        self.target = target
    }
}

struct EvidenceItem: Identifiable, Codable {
    let id: UUID
    var label: String
    var value: String

    init(id: UUID = UUID(), label: String, value: String) {
        self.id = id
        self.label = label
        self.value = value
    }
}

struct AgentNote: Identifiable, Codable {
    let id: UUID
    var agentName: String
    var summary: String
    var symbolName: String

    init(id: UUID = UUID(), agentName: String, summary: String, symbolName: String) {
        self.id = id
        self.agentName = agentName
        self.summary = summary
        self.symbolName = symbolName
    }
}

struct ExecutionLog: Identifiable, Codable {
    let id: UUID
    let createdAt: Date
    var message: String
    var isError: Bool

    init(id: UUID = UUID(), createdAt: Date = .now, message: String, isError: Bool = false) {
        self.id = id
        self.createdAt = createdAt
        self.message = message
        self.isError = isError
    }
}

// MARK: - SwiftData Models

@Model
final class Commitment {
    @Attribute(.unique) var id: UUID
    var title: String
    var owner: String
    var priority: String
    var deadline: Date?
    var reminderDate: Date?
    var sourceProofID: UUID?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        owner: String,
        priority: Priority,
        deadline: Date?,
        reminderDate: Date?,
        sourceProofID: UUID?
    ) {
        self.id = id
        self.title = title
        self.owner = owner
        self.priority = priority.rawValue
        self.deadline = deadline
        self.reminderDate = reminderDate
        self.sourceProofID = sourceProofID
        self.createdAt = .now
    }
}

@Model
final class WaitingItem {
    @Attribute(.unique) var id: UUID
    var title: String
    var responsibleParty: String
    var followUpDate: Date?
    var sourceProofID: UUID?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        responsibleParty: String,
        followUpDate: Date?,
        sourceProofID: UUID?
    ) {
        self.id = id
        self.title = title
        self.responsibleParty = responsibleParty
        self.followUpDate = followUpDate
        self.sourceProofID = sourceProofID
        self.createdAt = .now
    }
}

@Model
final class SourceProof {
    @Attribute(.unique) var id: UUID
    var rawInput: String
    var detectedSourceType: String
    var originalSource: String
    var thumbnailPath: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        rawInput: String,
        detectedSourceType: IntakeSourceKind,
        originalSource: String,
        thumbnailPath: String? = nil
    ) {
        self.id = id
        self.rawInput = rawInput
        self.detectedSourceType = detectedSourceType.rawValue
        self.originalSource = originalSource
        self.thumbnailPath = thumbnailPath
        self.createdAt = .now
    }
}

// Stores full AgentAnalysis as JSON so nothing is lost on restart.
@Model
final class StoredAnalysis {
    @Attribute(.unique) var id: UUID
    var jsonData: Data
    var intakeTitle: String
    var classificationRaw: String
    var createdAt: Date

    init(id: UUID, jsonData: Data, intakeTitle: String, classificationRaw: String, createdAt: Date) {
        self.id = id
        self.jsonData = jsonData
        self.intakeTitle = intakeTitle
        self.classificationRaw = classificationRaw
        self.createdAt = createdAt
    }

    func decode() -> AgentAnalysis? {
        try? JSONDecoder().decode(AgentAnalysis.self, from: jsonData)
    }
}
