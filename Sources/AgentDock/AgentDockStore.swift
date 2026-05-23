import AppKit
import Foundation
import SwiftData

@MainActor
final class AgentDockStore: ObservableObject {
    @Published var intakeItems: [IntakeItem] = []
    @Published var analyses: [AgentAnalysis] = []
    @Published var selectedAnalysisID: UUID?
    @Published var draftText = ""
    @Published var selectedSource: IntakeSourceKind = .clipboard
    @Published var isProcessing = false
    @Published var sourceDetectionBadge: String?
    @Published var activeAgents: Set<AgentRole> = []
    @Published var showingOnboarding = false
    @Published var editingAction: ProposedAction?

    let preferences: AppPreferences

    private let pipeline = AgentPipeline()
    private let intakeService = SmartIntakeService()
    private let openRouter = OpenRouterService.shared
    private let archive = SourceArchive.shared
    private let reminders = ReminderScheduler.shared
    private let executor = ConnectorExecutor.shared
    private var modelContext: ModelContext?
    private var lastDropSignature = ""
    private var lastDropDate = Date.distantPast

    init(preferences: AppPreferences) {
        self.preferences = preferences
        self.showingOnboarding = !preferences.onboardingCompleted

        Task {
            await reminders.requestAuthorization()
        }
    }

    var selectedAnalysis: AgentAnalysis? {
        guard let selectedAnalysisID else { return analyses.first }
        return analyses.first(where: { $0.id == selectedAnalysisID }) ?? analyses.first
    }

    var hasPendingItems: Bool {
        analyses.contains { !$0.commitments.isEmpty || !$0.followUps.isEmpty || !$0.proposedActions.isEmpty }
    }

    func attachModelContext(_ context: ModelContext) {
        modelContext = context
    }

    func ingestDraftText() {
        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draftText = ""

        runTask("draft-intake") {
            guard let item = await self.intakeService.itemFromText(text, preferredSource: self.selectedSource) else { return }
            await self.ingest(item)
        }
    }

    func ingestDroppedText(_ text: String) {
        guard shouldAcceptDrop(signature: text) else { return }

        runTask("text-drop-intake") {
            guard let item = await self.intakeService.itemFromText(text) else { return }
            await self.ingest(item)
        }
    }

    func ingestFiles(_ urls: [URL]) {
        guard shouldAcceptDrop(signature: urls.map(\.path).joined(separator: "|")) else { return }

        runTask("file-drop-intake") {
            await withTaskGroup(of: IntakeItem.self) { group in
                for url in urls {
                    group.addTask {
                        await self.intakeService.itemFromFile(url)
                    }
                }

                for await item in group {
                    await self.ingest(item)
                }
            }
        }
    }

    func approve(_ action: ProposedAction) {
        guard let index = analyses.firstIndex(where: { analysis in
            analysis.proposedActions.contains(where: { $0.id == action.id })
        }) else { return }

        analyses[index].executionLogs.append(ExecutionLog(message: "User approved '\(action.title)'.")) 

        runTask("approve-action") {
            let logs = await self.executor.execute(action)
            if let updatedIndex = self.analyses.firstIndex(where: { analysis in
                analysis.proposedActions.contains(where: { $0.id == action.id })
            }) {
                self.analyses[updatedIndex].executionLogs.append(contentsOf: logs)
                self.analyses[updatedIndex].notes.append(
                    AgentNote(
                        agentName: "Approval Agent",
                        summary: "Approved '\(action.title)' for \(action.tool.rawValue).",
                        symbolName: "checkmark.seal"
                    )
                )
            }
        }
    }

    func snoozeCommitment(_ commitment: CommitmentDraft, option: SnoozeOption) {
        runTask("snooze-commitment") {
            await self.reminders.schedule(
                title: commitment.title,
                body: "Snoozed AgentDock commitment",
                date: option.date
            )
        }
    }

    func clearAll() {
        intakeItems.removeAll()
        analyses.removeAll()
        selectedAnalysisID = nil
    }

    func panelDidClose() {
        guard analyses.count > 50 else { return }
        let archiveItems = Array(analyses.suffix(30))
        analyses.removeLast(min(30, analyses.count))

        runTask("archive-old-analyses") {
            await self.archive.archiveOldAnalyses(archiveItems)
        }
    }

    private func ingest(_ item: IntakeItem) async {
        isProcessing = true
        sourceDetectionBadge = item.sourceBadge
        activeAgents = Set(AgentRole.allCases)
        intakeItems.insert(item, at: 0)

        let proofRecord = await archive.saveSourceProof(for: item)
        let proof = persist(proofRecord)

        let analysis: AgentAnalysis
        if let apiKey = await preferences.loadAPIKey() {
            do {
                analysis = try await openRouter.analyze(
                    item: item,
                    apiKey: apiKey,
                    selectedModel: preferences.selectedModel
                )
            } catch {
                await CrashReporter.shared.log(error, context: "openrouter-analysis")
                var fallback = pipeline.analyze(item)
                fallback.notes.append(
                    AgentNote(
                        agentName: "AI Router",
                        summary: "OpenRouter failed, so AgentDock used local extraction: \(error.localizedDescription)",
                        symbolName: "exclamationmark.triangle"
                    )
                )
                analysis = fallback
            }
        } else {
            analysis = pipeline.analyze(item)
        }

        saveAnalysis(analysis, proofID: proof.id)
        analyses.insert(analysis, at: 0)
        selectedAnalysisID = analysis.id
        isProcessing = false
        activeAgents = []
        NSSound(named: "Pop")?.play()

        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                self.sourceDetectionBadge = nil
            }
        }
    }

    private func saveAnalysis(_ analysis: AgentAnalysis, proofID: UUID) {
        for commitment in analysis.commitments where !isDuplicateCommitment(commitment) {
            let reminderDate = DateParser.date(from: commitment.deadline)
                ?? Calendar.current.date(byAdding: .day, value: 1, to: .now)
            let stored = Commitment(
                title: commitment.title,
                owner: commitment.owner,
                priority: commitment.priority,
                deadline: DateParser.date(from: commitment.deadline),
                reminderDate: reminderDate,
                sourceProofID: proofID
            )
            modelContext?.insert(stored)

            runTask("commitment-reminder") {
                await self.reminders.schedule(
                    title: commitment.title,
                    body: commitment.sourceProof,
                    date: reminderDate
                )
            }
        }

        for followUp in analysis.followUps {
            let followUpDate = DateParser.date(from: followUp.checkBack)
                ?? Calendar.current.date(byAdding: .day, value: 2, to: .now)
            modelContext?.insert(
                WaitingItem(
                    title: followUp.title,
                    responsibleParty: followUp.responsibleParty,
                    followUpDate: followUpDate,
                    sourceProofID: proofID
                )
            )

            runTask("followup-reminder") {
                await self.reminders.schedule(
                    title: followUp.title,
                    body: "Follow up with \(followUp.responsibleParty)",
                    date: followUpDate
                )
            }
        }

        try? modelContext?.save()
    }

    private func persist(_ proof: ArchivedSourceProof) -> SourceProof {
        let sourceProof = SourceProof(
            id: proof.id,
            rawInput: proof.rawInput,
            detectedSourceType: proof.detectedSourceType,
            originalSource: proof.originalSource,
            thumbnailPath: proof.thumbnailPath
        )
        modelContext?.insert(sourceProof)
        try? modelContext?.save()
        return sourceProof
    }

    private func isDuplicateCommitment(_ commitment: CommitmentDraft) -> Bool {
        guard let modelContext else { return false }
        let descriptor = FetchDescriptor<Commitment>()
        guard let existing = try? modelContext.fetch(descriptor) else { return false }

        return existing.contains { stored in
            FuzzyMatcher.normalizedLevenshtein(stored.title, commitment.title) < 0.2
        }
    }

    private func shouldAcceptDrop(signature: String) -> Bool {
        let now = Date()
        defer {
            lastDropSignature = signature
            lastDropDate = now
        }

        if signature == lastDropSignature, now.timeIntervalSince(lastDropDate) < 0.15 {
            return false
        }

        return true
    }

    private func runTask(_ context: String, operation: @escaping @MainActor () async -> Void) {
        Task {
            await CrashReporter.shared.log(message: "task-start \(context)")
            await operation()
        }
    }
}

enum DateParser {
    static func date(from text: String?) -> Date? {
        guard let text else { return nil }
        let lower = text.lowercased()
        let calendar = Calendar.current

        if lower.contains("today") || lower.contains("eod") {
            return calendar.date(bySettingHour: 17, minute: 0, second: 0, of: .now)
        }

        if lower.contains("tomorrow") {
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now) ?? .now
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)
        }

        if lower.contains("week") {
            return calendar.date(byAdding: .day, value: 7, to: .now)
        }

        return nil
    }
}

enum FuzzyMatcher {
    static func normalizedLevenshtein(_ lhs: String, _ rhs: String) -> Double {
        let left = Array(lhs.lowercased())
        let right = Array(rhs.lowercased())
        guard !left.isEmpty || !right.isEmpty else { return 0 }

        var distances = Array(0...right.count)
        for (leftIndex, leftCharacter) in left.enumerated() {
            var previous = distances[0]
            distances[0] = leftIndex + 1

            for (rightIndex, rightCharacter) in right.enumerated() {
                let old = distances[rightIndex + 1]
                distances[rightIndex + 1] = min(
                    distances[rightIndex + 1] + 1,
                    distances[rightIndex] + 1,
                    previous + (leftCharacter == rightCharacter ? 0 : 1)
                )
                previous = old
            }
        }

        return Double(distances[right.count]) / Double(max(left.count, right.count))
    }
}
