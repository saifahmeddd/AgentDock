import Foundation
import SwiftData

enum IntakeSourceKind: String, CaseIterable, Identifiable {
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

enum Priority: String, CaseIterable, Identifiable {
    case low = "Low"
    case normal = "Normal"
    case high = "High"
    case urgent = "Urgent"

    var id: String { rawValue }
}

enum ActionTool: String, CaseIterable, Identifiable {
    case gmail = "Gmail"
    case calendar = "Calendar"
    case notion = "Notion"
    case linear = "Linear"
    case slack = "Slack"
    case microsoft365 = "Microsoft 365"

    var id: String { rawValue }
}

enum WorkClassification: String {
    case humanTask = "Human task"
    case waitingItem = "Waiting item"
    case aiAction = "AI-doable action"
    case referenceOnly = "Reference only"
}

enum AgentRole: String, CaseIterable, Identifiable {
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

enum OpenRouterModel: String, CaseIterable, Identifiable {
    case grokMini = "x-ai/grok-3-mini"
    case geminiFlash = "google/gemini-2.5-flash"
    case mistralSmall = "mistralai/mistral-small"
    case claudeSonnet = "anthropic/claude-sonnet-4.5"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .grokMini: "Grok 3 Mini"
        case .geminiFlash: "Gemini Flash 2.5"
        case .mistralSmall: "Mistral Small"
        case .claudeSonnet: "Claude Sonnet 4.5"
        }
    }

    var inputPricePerMillionTokens: Decimal {
        switch self {
        case .grokMini: Decimal(string: "0.30") ?? 0
        case .geminiFlash: Decimal(string: "0.30") ?? 0
        case .mistralSmall: Decimal(string: "0.10") ?? 0
        case .claudeSonnet: Decimal(string: "3.00") ?? 0
        }
    }

    var outputPricePerMillionTokens: Decimal {
        switch self {
        case .grokMini: Decimal(string: "0.50") ?? 0
        case .geminiFlash: Decimal(string: "2.50") ?? 0
        case .mistralSmall: Decimal(string: "0.30") ?? 0
        case .claudeSonnet: Decimal(string: "15.00") ?? 0
        }
    }

    static let fallback: OpenRouterModel = .grokMini
}

enum VerificationStatus: Equatable {
    case unknown
    case verifying
    case valid(String)
    case invalid(String)
}

struct IntakeItem: Identifiable, Equatable {
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

struct AgentAnalysis: Identifiable {
    let id = UUID()
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
    var estimatedCost: Decimal?
    var usedFallback: Bool
    var executionLogs: [ExecutionLog]
    var activeAgents: Set<AgentRole>

    var costLabel: String {
        guard let estimatedCost else { return "Local analysis" }
        return "$" + NSDecimalNumber(decimal: estimatedCost).stringValue
    }
}

struct CommitmentDraft: Identifiable {
    let id = UUID()
    var title: String
    var owner: String
    var priority: Priority
    var deadline: String?
    var reminder: String
    var sourceProof: String
}

struct FollowUpDraft: Identifiable {
    let id = UUID()
    var title: String
    var responsibleParty: String
    var checkBack: String
    var sourceProof: String
}

struct ProposedAction: Identifiable {
    let id = UUID()
    var title: String
    var tool: ActionTool
    var approvalPrompt: String
    var sourceProof: String
    var details: String
    var target: String?

    init(
        title: String,
        tool: ActionTool,
        approvalPrompt: String,
        sourceProof: String,
        details: String = "",
        target: String? = nil
    ) {
        self.title = title
        self.tool = tool
        self.approvalPrompt = approvalPrompt
        self.sourceProof = sourceProof
        self.details = details
        self.target = target
    }
}

struct EvidenceItem: Identifiable {
    let id = UUID()
    var label: String
    var value: String
}

struct AgentNote: Identifiable {
    let id = UUID()
    var agentName: String
    var summary: String
    var symbolName: String
}

struct ExecutionLog: Identifiable {
    let id = UUID()
    let createdAt: Date
    var message: String
    var isError: Bool

    init(createdAt: Date = .now, message: String, isError: Bool = false) {
        self.createdAt = createdAt
        self.message = message
        self.isError = isError
    }
}

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
