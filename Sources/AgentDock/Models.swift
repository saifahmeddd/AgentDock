import Foundation

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

struct IntakeItem: Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    var title: String
    var body: String
    var sourceKind: IntakeSourceKind
    var originalSource: String
    var attachments: [URL]

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        title: String,
        body: String,
        sourceKind: IntakeSourceKind,
        originalSource: String,
        attachments: [URL] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.title = title
        self.body = body
        self.sourceKind = sourceKind
        self.originalSource = originalSource
        self.attachments = attachments
    }
}

struct AgentAnalysis: Identifiable {
    let id = UUID()
    let intake: IntakeItem
    var classification: WorkClassification
    var commitments: [Commitment]
    var followUps: [FollowUp]
    var proposedActions: [ProposedAction]
    var evidence: [EvidenceItem]
    var notes: [AgentNote]
}

struct Commitment: Identifiable {
    let id = UUID()
    var title: String
    var owner: String
    var priority: Priority
    var deadline: String?
    var reminder: String
    var sourceProof: String
}

struct FollowUp: Identifiable {
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
