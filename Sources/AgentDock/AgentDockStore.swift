import AppKit
import Foundation
import SwiftData

// MARK: - ConnectorAuthState

// Tracks which connectors have actually been configured. Stored in UserDefaults.
// OAuth tokens are stored separately in Keychain; this just records what's connected.
enum ConnectorAuthState: String {
    case notConnected
    case connectedViaSystem  // EventKit, mailto — no token needed
    case connected           // OAuth token present in Keychain
}

// MARK: - AgentDockStore

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
    @Published var hotkeyPermissionMissing = false

    let preferences: AppPreferences

    private let pipeline = AgentPipeline()
    private let intakeService = SmartIntakeService()
    private let llmService = LLMService.shared
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
        loadPersistedAnalyses()
    }

    // MARK: - Intake entry points

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

    // MARK: - Approval

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
                self.persistAnalysis(self.analyses[updatedIndex])
            }
        }
    }

    func toggleCommitmentDone(id: UUID, inAnalysisID: UUID) {
        guard let aIdx = analyses.firstIndex(where: { $0.id == inAnalysisID }),
              let cIdx = analyses[aIdx].commitments.firstIndex(where: { $0.id == id }) else { return }
        analyses[aIdx].commitments[cIdx].isDone.toggle()
        persistAnalysis(analyses[aIdx])
    }

    func toggleFollowUpDone(id: UUID, inAnalysisID: UUID) {
        guard let aIdx = analyses.firstIndex(where: { $0.id == inAnalysisID }),
              let fIdx = analyses[aIdx].followUps.firstIndex(where: { $0.id == id }) else { return }
        analyses[aIdx].followUps[fIdx].isDone.toggle()
        persistAnalysis(analyses[aIdx])
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

        // Remove archived analyses from SwiftData too.
        if let context = modelContext {
            for analysis in archiveItems {
                removeStoredAnalysis(id: analysis.id, context: context)
            }
        }

        runTask("archive-old-analyses") {
            await self.archive.archiveOldAnalyses(archiveItems)
        }
    }

    // MARK: - Private: Core Pipeline

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
                analysis = try await llmService.analyze(
                    item: item,
                    apiKey: apiKey,
                    selectedModel: preferences.selectedModel
                )
            } catch {
                await CrashReporter.shared.log(error, context: "nim-analysis")
                var fallback = pipeline.analyze(item)
                fallback.notes.append(
                    AgentNote(
                        agentName: "AI Router",
                        summary: "NVIDIA NIM failed — used local extraction. \(error.localizedDescription)",
                        symbolName: "exclamationmark.triangle"
                    )
                )
                analysis = fallback
            }
        } else {
            analysis = pipeline.analyze(item)
        }

        saveAnalysis(analysis, proofID: proof.id)
        persistAnalysis(analysis)

        analyses.insert(analysis, at: 0)
        selectedAnalysisID = analysis.id
        isProcessing = false
        activeAgents = []
        NSSound(named: "Pop")?.play()

        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            sourceDetectionBadge = nil
        }
    }

    // MARK: - Private: SwiftData persistence

    private func loadPersistedAnalyses() {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<StoredAnalysis>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        guard let stored = try? context.fetch(descriptor) else { return }
        let loaded = stored.compactMap { $0.decode() }
        // Only load analyses that aren't already in memory (avoid duplicates if called twice).
        let existingIDs = Set(analyses.map(\.id))
        let newAnalyses = loaded.filter { !existingIDs.contains($0.id) }
        analyses.append(contentsOf: newAnalyses)
    }

    private func persistAnalysis(_ analysis: AgentAnalysis) {
        guard let context = modelContext else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(analysis) else { return }

        // Upsert: remove existing record with same id if present, then insert fresh.
        removeStoredAnalysis(id: analysis.id, context: context)
        let stored = StoredAnalysis(
            id: analysis.id,
            jsonData: data,
            intakeTitle: analysis.intake.title,
            classificationRaw: analysis.classification.rawValue,
            createdAt: analysis.intake.createdAt
        )
        context.insert(stored)
        try? context.save()
    }

    private func removeStoredAnalysis(id: UUID, context: ModelContext) {
        let predicate = #Predicate<StoredAnalysis> { $0.id == id }
        let descriptor = FetchDescriptor<StoredAnalysis>(predicate: predicate)
        guard let existing = try? context.fetch(descriptor) else { return }
        for record in existing {
            context.delete(record)
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

            if let reminderDate {
                runTask("commitment-reminder") {
                    await self.reminders.schedule(
                        title: commitment.title,
                        body: commitment.sourceProof,
                        date: reminderDate
                    )
                }
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

            if let followUpDate {
                runTask("followup-reminder") {
                    await self.reminders.schedule(
                        title: followUp.title,
                        body: "Follow up with \(followUp.responsibleParty)",
                        date: followUpDate
                    )
                }
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

// MARK: - DateParser

enum DateParser {
    static func date(from text: String?) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        let lower = text.lowercased()
        let calendar = Calendar.current

        // Absolute keywords
        if lower.contains("today") || lower.contains("eod") || lower.contains("end of day") {
            return calendar.date(bySettingHour: 17, minute: 0, second: 0, of: .now)
        }
        if lower.contains("tomorrow") {
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now) ?? .now
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)
        }
        if lower.contains("next week") || lower.contains("week") {
            return calendar.date(byAdding: .day, value: 7, to: .now)
        }

        // "next <weekday>" or plain "<weekday>"
        let weekdays = ["sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4,
                        "thursday": 5, "friday": 6, "saturday": 7]
        for (name, weekday) in weekdays {
            if lower.contains(name) {
                let isNext = lower.contains("next \(name)")
                if let target = nextWeekday(weekday, from: .now, forceNextWeek: isNext) {
                    return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: target)
                }
            }
        }

        // "Month Day" — e.g. "March 14", "Jan 3"
        if let date = parseMonthDay(from: text) {
            return date
        }

        // MM/DD or MM/DD/YYYY
        if let date = parseNumericDate(from: lower) {
            return date
        }

        // ISO 8601 date component e.g. "2025-03-14"
        let isoFormatter = DateFormatter()
        isoFormatter.dateFormat = "yyyy-MM-dd"
        let words = text.components(separatedBy: .whitespacesAndNewlines)
        for word in words {
            if let date = isoFormatter.date(from: word.trimmingCharacters(in: .punctuationCharacters)) {
                return date
            }
        }

        return nil
    }

    private static func nextWeekday(_ weekday: Int, from date: Date, forceNextWeek: Bool) -> Date? {
        let calendar = Calendar.current
        let currentWeekday = calendar.component(.weekday, from: date)
        var daysAhead = weekday - currentWeekday
        if daysAhead <= 0 || forceNextWeek {
            daysAhead += 7
        }
        return calendar.date(byAdding: .day, value: daysAhead, to: date)
    }

    private static func parseMonthDay(from text: String) -> Date? {
        let monthNames = [
            "january": 1, "february": 2, "march": 3, "april": 4,
            "may": 5, "june": 6, "july": 7, "august": 8,
            "september": 9, "october": 10, "november": 11, "december": 12,
            "jan": 1, "feb": 2, "mar": 3, "apr": 4,
            "jun": 6, "jul": 7, "aug": 8, "sep": 9, "sept": 9,
            "oct": 10, "nov": 11, "dec": 12
        ]

        let pattern = #"(january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sep|sept|oct|nov|dec)\s+(\d{1,2})"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        guard match.numberOfRanges >= 3,
              let monthRange = Range(match.range(at: 1), in: text),
              let dayRange = Range(match.range(at: 2), in: text),
              let monthNum = monthNames[String(text[monthRange]).lowercased()],
              let dayNum = Int(text[dayRange]) else { return nil }

        let calendar = Calendar.current
        var components = calendar.dateComponents([.year], from: .now)
        components.month = monthNum
        components.day = dayNum
        components.hour = 9
        components.minute = 0

        guard let candidate = calendar.date(from: components) else { return nil }
        // If the date has already passed this year, use next year.
        return candidate > .now ? candidate : calendar.date(byAdding: .year, value: 1, to: candidate)
    }

    private static func parseNumericDate(from text: String) -> Date? {
        let pattern = #"\b(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }

        guard let mRange = Range(match.range(at: 1), in: text),
              let dRange = Range(match.range(at: 2), in: text),
              let month = Int(text[mRange]),
              let day = Int(text[dRange]),
              (1...12).contains(month),
              (1...31).contains(day) else { return nil }

        let calendar = Calendar.current
        var components = DateComponents()
        if match.numberOfRanges >= 4, match.range(at: 3).location != NSNotFound,
           let yRange = Range(match.range(at: 3), in: text),
           var year = Int(text[yRange]) {
            if year < 100 { year += 2000 }
            components.year = year
        } else {
            components.year = calendar.component(.year, from: .now)
        }
        components.month = month
        components.day = day
        components.hour = 9

        guard let candidate = calendar.date(from: components) else { return nil }
        if candidate < .now, components.year == calendar.component(.year, from: .now) {
            return calendar.date(byAdding: .year, value: 1, to: candidate)
        }
        return candidate
    }
}

// MARK: - FuzzyMatcher

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
