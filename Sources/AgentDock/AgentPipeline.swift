import Foundation

struct AgentPipeline {
    func analyze(_ item: IntakeItem) -> AgentAnalysis {
        let normalizedBody = item.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let signals = Signals(text: normalizedBody)
        let snippets = sourceSnippets(from: normalizedBody)

        var commitments = buildCommitments(item: item, signals: signals, snippets: snippets)
        let followUps = buildFollowUps(item: item, signals: signals, snippets: snippets)
        let proposedActions = buildProposedActions(item: item, signals: signals, snippets: snippets)

        if commitments.isEmpty, followUps.isEmpty, proposedActions.isEmpty, !normalizedBody.isEmpty {
            commitments.append(
                CommitmentDraft(
                    title: fallbackTitle(from: normalizedBody),
                    owner: "You",
                    priority: signals.priority,
                    deadline: signals.deadline,
                    reminder: signals.deadline.map { "Remind before \($0)" } ?? "Remind tomorrow morning",
                    sourceProof: snippets.first ?? normalizedBody
                )
            )
        }

        let classification: WorkClassification
        if !proposedActions.isEmpty {
            classification = .aiAction
        } else if !followUps.isEmpty {
            classification = .waitingItem
        } else if !commitments.isEmpty {
            classification = .humanTask
        } else {
            classification = .referenceOnly
        }

        return AgentAnalysis(
            intake: item,
            classification: classification,
            commitments: commitments,
            followUps: followUps,
            proposedActions: proposedActions,
            evidence: buildEvidence(item: item, signals: signals),
            notes: buildNotes(classification: classification, signals: signals, item: item),
            usedFallback: false,
            executionLogs: []
        )
    }

    private func buildCommitments(item: IntakeItem, signals: Signals, snippets: [String]) -> [CommitmentDraft] {
        guard signals.hasTaskLanguage || signals.hasPromiseLanguage else { return [] }

        return [
            CommitmentDraft(
                title: taskTitle(from: item.body),
                owner: signals.owner,
                priority: signals.priority,
                deadline: signals.deadline,
                reminder: signals.deadline.map { "Remind 2 hours before \($0)" } ?? "Remind tomorrow at 9:00 AM",
                sourceProof: snippets.first ?? item.body
            )
        ]
    }

    private func buildFollowUps(item: IntakeItem, signals: Signals, snippets: [String]) -> [FollowUpDraft] {
        guard signals.hasWaitingLanguage else { return [] }

        return [
            FollowUpDraft(
                title: followUpTitle(from: item.body),
                responsibleParty: signals.responsibleParty,
                checkBack: signals.deadline.map { "Check back on \($0)" } ?? "Check back in 2 business days",
                sourceProof: snippets.first ?? item.body
            )
        ]
    }

    private func buildProposedActions(item: IntakeItem, signals: Signals, snippets: [String]) -> [ProposedAction] {
        var actions: [ProposedAction] = []

        if signals.requestsEmail {
            actions.append(
                ProposedAction(
                    title: "Draft email response",
                    tool: .gmail,
                    approvalPrompt: "Review and approve the email draft before sending.",
                    sourceProof: snippets.first ?? item.body
                )
            )
        }

        if signals.requestsMeeting {
            actions.append(
                ProposedAction(
                    title: "Prepare calendar hold",
                    tool: .calendar,
                    approvalPrompt: "Confirm attendees and time before creating the event.",
                    sourceProof: snippets.first ?? item.body
                )
            )
        }

        if signals.requestsTicket {
            actions.append(
                ProposedAction(
                    title: "Create implementation ticket",
                    tool: .linear,
                    approvalPrompt: "Approve the extracted scope before creating the Linear issue.",
                    sourceProof: snippets.first ?? item.body
                )
            )
        }

        if signals.requestsKnowledgeSave {
            actions.append(
                ProposedAction(
                    title: "Save source note",
                    tool: .notion,
                    approvalPrompt: "Approve the destination page before saving the note.",
                    sourceProof: snippets.first ?? item.body
                )
            )
        }

        return actions
    }

    private func buildEvidence(item: IntakeItem, signals: Signals) -> [EvidenceItem] {
        var evidence = [
            EvidenceItem(label: "Original source", value: item.originalSource),
            EvidenceItem(label: "Detected source", value: item.sourceKind.rawValue)
        ]

        if let deadline = signals.deadline {
            evidence.append(EvidenceItem(label: "Deadline", value: deadline))
        }

        let people = signals.people
        if !people.isEmpty {
            evidence.append(EvidenceItem(label: "People", value: people.joined(separator: ", ")))
        }

        return evidence
    }

    private func buildNotes(classification: WorkClassification, signals: Signals, item: IntakeItem) -> [AgentNote] {
        [
            AgentNote(
                agentName: "Intake Agent",
                summary: "Captured \(item.sourceKind.rawValue.lowercased()) input and preserved source proof.",
                symbolName: "tray.and.arrow.down"
            ),
            AgentNote(
                agentName: "Commitment Agent",
                summary: "Classified as \(classification.rawValue.lowercased()) with \(signals.priority.rawValue.lowercased()) priority.",
                symbolName: "checklist"
            ),
            AgentNote(
                agentName: "Deadline Agent",
                summary: signals.deadline.map { "Found deadline signal: \($0)." } ?? "No explicit deadline found.",
                symbolName: "calendar.badge.clock"
            ),
            AgentNote(
                agentName: "Action Agent",
                summary: signals.hasAIActionLanguage
                    ? "Found tool-ready action language; approval required before execution."
                    : "No external tool execution required yet.",
                symbolName: "bolt.badge.checkmark"
            )
        ]
    }

    // MARK: - Title helpers

    private func taskTitle(from text: String) -> String {
        title(prefixes: ["please", "can you", "could you", "need to", "we need to", "i need to"], from: text)
    }

    private func followUpTitle(from text: String) -> String {
        title(prefixes: ["waiting on", "follow up", "checking back", "circle back"], from: text)
    }

    private func fallbackTitle(from text: String) -> String {
        let firstLine = text.components(separatedBy: .newlines).first ?? text
        return clipped(firstLine, limit: 78)
    }

    private func title(prefixes: [String], from text: String) -> String {
        let lower = text.lowercased()
        for prefix in prefixes where lower.contains(prefix) {
            if let range = lower.range(of: prefix) {
                let afterPrefix = text[range.upperBound...]
                    .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
                if !afterPrefix.isEmpty {
                    return clipped(String(afterPrefix), limit: 78)
                }
            }
        }
        return fallbackTitle(from: text)
    }

    private func sourceSnippets(from text: String) -> [String] {
        text.split(whereSeparator: { ".!?\n".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(3)
            .map { clipped($0, limit: 140) }
    }

    private func clipped(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        let end = text.index(text.startIndex, offsetBy: limit)
        return String(text[..<end]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}

// MARK: - Signals

private struct Signals {
    let text: String

    var lower: String { text.lowercased() }

    var hasTaskLanguage: Bool {
        containsAny(["please", "can you", "could you", "need to", "we need to", "todo",
                     "action item", "review", "send", "draft", "schedule", "prepare"])
    }

    var hasPromiseLanguage: Bool {
        containsAny(["i'll", "i will", "we will", "i can", "we can", "promise", "committed to"])
    }

    var hasWaitingLanguage: Bool {
        containsAny(["waiting on", "blocked by", "follow up", "circle back",
                     "checking back", "haven't heard", "hasn't replied"])
    }

    var hasAIActionLanguage: Bool {
        requestsEmail || requestsMeeting || requestsTicket || requestsKnowledgeSave
    }

    var requestsEmail: Bool {
        containsAny(["email", "reply", "respond", "send a note", "draft"])
    }

    var requestsMeeting: Bool {
        containsAny(["meeting", "calendar", "schedule", "book time", "call"])
    }

    var requestsTicket: Bool {
        containsAny(["linear", "jira", "ticket", "issue", "bug", "feature request"])
    }

    var requestsKnowledgeSave: Bool {
        containsAny(["notion", "save this", "document this", "write up", "notes"])
    }

    var priority: Priority {
        if containsAny(["urgent", "asap", "immediately", "today", "eod", "end of day"]) {
            return .urgent
        }
        if containsAny(["important", "high priority", "before launch", "blocked"]) {
            return .high
        }
        if containsAny(["when you can", "low priority", "no rush"]) {
            return .low
        }
        return .normal
    }

    var owner: String {
        if containsAny(["i'll", "i will", "i need to"]) { return "You" }
        if containsAny(["we need to", "we should", "we will"]) { return "Team" }
        return "You"
    }

    var responsibleParty: String {
        // Try to extract a name after "waiting on" or "blocked by"
        if let match = firstNameMatch(after: "waiting on") { return match }
        if let match = firstNameMatch(after: "blocked by") { return match }
        return "Other person"
    }

    var deadline: String? {
        if containsAny(["today", "eod", "end of day"]) { return "today" }
        if containsAny(["tomorrow"]) { return "tomorrow" }
        // "by/before/on <weekday>"
        if let match = firstMatch(pattern: #"(?:by|before|on)\s+(?:next\s+)?(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday)"#,
                                  captureGroup: 1) {
            return match
        }
        // "by/before/on <Month Day>"
        if let match = firstMatch(
            pattern: #"(?:by|before|on)\s+([A-Z][a-z]+\s+\d{1,2}(?:st|nd|rd|th)?)"#,
            captureGroup: 1) {
            return match
        }
        // MM/DD
        if let match = firstMatch(pattern: #"\b(\d{1,2}/\d{1,2}(?:/\d{2,4})?)\b"#, captureGroup: 1) {
            return match
        }
        // next week / in N days
        if containsAny(["next week"]) { return "next week" }
        return nil
    }

    // Names: require Title Case First + Last OR known-name patterns.
    // Excludes common English words, sentence starters, and noise words to avoid false positives.
    var people: [String] {
        let stopWords: Set<String> = [
            "I", "We", "The", "This", "These", "Those", "That", "A", "An",
            "Please", "Can", "Could", "Should", "Would", "Will", "Shall",
            "He", "She", "It", "They", "You", "Me", "Us", "Him", "Her",
            "My", "Our", "Your", "Their", "Its", "His",
            "And", "Or", "But", "For", "Nor", "So", "Yet",
            "From", "To", "In", "On", "At", "By", "Of", "As", "Up",
            "Hi", "Hey", "Dear", "Hello", "Thanks", "Thank",
            "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday",
            "January", "February", "March", "April", "May", "June",
            "July", "August", "September", "October", "November", "December",
            "Linear", "Notion", "Slack", "Gmail", "Google", "Apple", "Microsoft",
            "Jira", "GitHub", "Teams", "Zoom", "Figma",
            "OK", "Yes", "No", "Not", "Also", "Just", "Still", "Already",
            "Today", "Tomorrow", "Next", "Last", "Now", "Then"
        ]

        // Require First + Last name pattern (two title-case words) to reduce noise.
        let fullNamePattern = #"\b([A-Z][a-z]{1,19}\s[A-Z][a-z]{1,19})\b"#

        var found: [String] = []

        // Full names first — high precision
        let fullNames = matches(pattern: fullNamePattern)
            .filter { name in
                let parts = name.components(separatedBy: " ")
                return parts.count == 2 && parts.allSatisfy { !stopWords.contains($0) }
            }
        found.append(contentsOf: fullNames)

        // Single-word names only if after "waiting on", "blocked by", "from:", "@"
        let contextualPatterns = [
            #"waiting on ([A-Z][a-z]{2,19})\b"#,
            #"blocked by ([A-Z][a-z]{2,19})\b"#,
            #"[Ff]rom:\s*([A-Z][a-z]{2,19})\b"#,
            #"@([A-Za-z][a-z]{2,19})\b"#
        ]
        for pattern in contextualPatterns {
            let contextMatches = matches(pattern: pattern)
                .filter { !stopWords.contains($0) }
            found.append(contentsOf: contextMatches)
        }

        // Deduplicate while preserving order
        var seen = Set<String>()
        return found.filter { seen.insert($0).inserted }.prefix(5).map { $0 }
    }

    private func containsAny(_ candidates: [String]) -> Bool {
        candidates.contains { lower.contains($0) }
    }

    private func firstMatch(pattern: String, captureGroup: Int = 1) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let result = regex.firstMatch(in: text, range: nsRange) else { return nil }
        let range = captureGroup < result.numberOfRanges ? result.range(at: captureGroup) : result.range
        guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else { return nil }
        return String(text[swiftRange])
    }

    private func firstNameMatch(after keyword: String) -> String? {
        let pattern = "\(NSRegularExpression.escapedPattern(for: keyword))\\s+([A-Z][a-z]{2,19}(?:\\s[A-Z][a-z]{2,19})?)"
        return firstMatch(pattern: pattern, captureGroup: 1)
    }

    private func matches(pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: nsRange).compactMap { result in
            let captureGroup = result.numberOfRanges > 1 ? result.range(at: 1) : result.range
            guard let swiftRange = Range(captureGroup, in: text) else { return nil }
            return String(text[swiftRange])
        }
    }
}
