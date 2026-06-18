import SwiftUI

// MARK: - AnalysisDetailView

struct AnalysisDetailView: View {
    @EnvironmentObject private var store: AgentDockStore
    let analysis: AgentAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AnalysisHeaderRow(analysis: analysis)

            if analysis.usedFallback {
                FallbackBanner()
            }

            if !analysis.commitments.isEmpty {
                let pending = analysis.commitments.filter { !$0.isDone }
                let done = analysis.commitments.filter { $0.isDone }

                SectionHeader(
                    title: done.isEmpty ? "Commitments" : "Commitments (\(done.count)/\(analysis.commitments.count) done)",
                    symbol: "checkmark.circle.fill",
                    color: .orange
                )

                ForEach(pending) { commitment in
                    CommitmentCard(commitment: commitment, analysis: analysis)
                }

                if !done.isEmpty {
                    DisclosureGroup {
                        ForEach(done) { commitment in
                            CommitmentCard(commitment: commitment, analysis: analysis)
                        }
                    } label: {
                        Label("Done (\(done.count))", systemImage: "checkmark.circle")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    }
                }
            }

            if !analysis.followUps.isEmpty {
                let pending = analysis.followUps.filter { !$0.isDone }
                let done = analysis.followUps.filter { $0.isDone }

                SectionHeader(
                    title: done.isEmpty ? "Follow-ups" : "Follow-ups (\(done.count)/\(analysis.followUps.count) done)",
                    symbol: "clock.arrow.circlepath",
                    color: .blue
                )

                ForEach(pending) { followUp in
                    FollowUpCard(followUp: followUp, analysis: analysis)
                }

                if !done.isEmpty {
                    DisclosureGroup {
                        ForEach(done) { followUp in
                            FollowUpCard(followUp: followUp, analysis: analysis)
                        }
                    } label: {
                        Label("Done (\(done.count))", systemImage: "checkmark.circle")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    }
                }
            }

            if !analysis.proposedActions.isEmpty {
                SectionHeader(title: "Proposed Actions", symbol: "bolt.badge.checkmark.fill", color: .green)
                ForEach(analysis.proposedActions) { action in
                    ApprovalCard(action: action, costLabel: analysis.costLabel)
                }
            }

            if !analysis.executionLogs.isEmpty {
                ExecutionLogView(logs: analysis.executionLogs)
            }

            DisclosureGroup {
                VStack(spacing: 8) {
                    ForEach(analysis.notes) { note in
                        AgentNoteRow(note: note)
                    }
                }
                .padding(.top, 8)
            } label: {
                Label("Agent Squad", systemImage: "person.3.fill")
                    .font(.subheadline.weight(.semibold))
            }

            DisclosureGroup {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(analysis.evidence) { evidence in
                        HStack(alignment: .firstTextBaseline) {
                            Text(evidence.label)
                                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                                .frame(width: 92, alignment: .leading)
                            Text(evidence.value)
                                .lineLimit(3)
                                .textSelection(.enabled)
                            Spacer(minLength: 0)
                        }
                        .font(.caption)
                    }

                    Divider()
                        .padding(.vertical, 4)

                    Text(analysis.intake.body)
                        .font(.caption)
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                        .lineLimit(5)
                        .textSelection(.enabled)
                }
                .padding(.top, 8)
            } label: {
                Label("Source Proof", systemImage: "paperclip")
                    .font(.subheadline.weight(.semibold))
            }

            if let modelID = analysis.modelID {
                CostFooter(modelID: modelID, costLabel: analysis.costLabel)
            }
        }
    }

    private func priorityColor(_ priority: Priority) -> Color {
        switch priority {
        case .urgent: .red
        case .high: .orange
        case .normal: Color(nsColor: .secondaryLabelColor)
        case .low: .blue
        }
    }
}

// MARK: - Supporting sub-views

private struct AnalysisHeaderRow: View {
    let analysis: AgentAnalysis

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: classificationSymbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(classificationColor)
                .frame(width: 28, height: 28)
                .background(classificationColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 3) {
                Text(analysis.intake.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(nsColor: .labelColor))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Label(analysis.classification.rawValue, systemImage: analysis.intake.sourceKind.symbolName)
                        .font(.caption2)
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    Text("·")
                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                        .font(.caption2)
                    Text(analysis.intake.createdAt, style: .time)
                        .font(.caption2)
                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                }
            }

            Spacer()
        }
    }

    private var classificationSymbol: String {
        switch analysis.classification {
        case .humanTask: "person.fill.checkmark"
        case .waitingItem: "clock.arrow.circlepath"
        case .aiAction: "bolt.fill"
        case .referenceOnly: "doc.text"
        }
    }

    private var classificationColor: Color {
        switch analysis.classification {
        case .humanTask: .orange
        case .waitingItem: .blue
        case .aiAction: .green
        case .referenceOnly: Color(nsColor: .secondaryLabelColor)
        }
    }
}

private struct FallbackBanner: View {
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .font(.caption)
            Text("AI unavailable — used local analysis. Results may be less precise.")
                .font(.caption)
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
    }
}

private struct SectionHeader: View {
    let title: String
    let symbol: String
    let color: Color

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
    }
}

private struct CostFooter: View {
    let modelID: String
    let costLabel: String

    var body: some View {
        HStack {
            Image(systemName: "sparkles")
                .font(.caption2)
                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
            Text(modelID)
                .font(.caption2)
                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
            Spacer()
            Text(costLabel)
                .font(.caption2)
                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
        }
    }
}

// MARK: - CommitmentCard / FollowUpCard

private struct CommitmentCard: View {
    @EnvironmentObject private var store: AgentDockStore
    let commitment: CommitmentDraft
    let analysis: AgentAnalysis

    var body: some View {
        WorkCard(
            accent: commitment.isDone ? Color(nsColor: .tertiaryLabelColor) : .orange,
            symbol: commitment.isDone ? "checkmark.circle.fill" : "circle",
            title: commitment.title,
            badge: commitment.isDone ? nil : commitment.priority.rawValue,
            badgeColor: priorityColor(commitment.priority),
            subtitle: commitment.owner,
            chip: commitment.deadline ?? commitment.reminder,
            chipSymbol: "calendar",
            isDone: commitment.isDone
        ) {
            HStack(spacing: 8) {
                if !commitment.isDone {
                    Menu {
                        ForEach(SnoozeOption.allCases) { option in
                            Button(option.rawValue) {
                                store.snoozeCommitment(commitment, option: option)
                            }
                        }
                    } label: {
                        Image(systemName: "bell.badge")
                            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    }
                    .menuStyle(.borderlessButton)
                    .help("Snooze reminder")
                }
                Button {
                    store.toggleCommitmentDone(id: commitment.id, inAnalysisID: analysis.id)
                } label: {
                    Image(systemName: commitment.isDone ? "arrow.uturn.backward.circle" : "checkmark.circle.fill")
                        .foregroundStyle(commitment.isDone ? Color(nsColor: .secondaryLabelColor) : .orange)
                }
                .buttonStyle(.borderless)
                .help(commitment.isDone ? "Mark undone" : "Mark done")
            }
        }
        .opacity(commitment.isDone ? 0.55 : 1)
    }

    private func priorityColor(_ priority: Priority) -> Color {
        switch priority {
        case .urgent: .red
        case .high: .orange
        case .normal: Color(nsColor: .secondaryLabelColor)
        case .low: .blue
        }
    }
}

private struct FollowUpCard: View {
    @EnvironmentObject private var store: AgentDockStore
    let followUp: FollowUpDraft
    let analysis: AgentAnalysis

    var body: some View {
        WorkCard(
            accent: followUp.isDone ? Color(nsColor: .tertiaryLabelColor) : .blue,
            symbol: followUp.isDone ? "checkmark.circle.fill" : "clock.arrow.circlepath",
            title: followUp.title,
            badge: nil,
            badgeColor: .clear,
            subtitle: followUp.responsibleParty,
            chip: followUp.checkBack,
            chipSymbol: "person",
            isDone: followUp.isDone
        ) {
            Button {
                store.toggleFollowUpDone(id: followUp.id, inAnalysisID: analysis.id)
            } label: {
                Image(systemName: followUp.isDone ? "arrow.uturn.backward.circle" : "checkmark.circle.fill")
                    .foregroundStyle(followUp.isDone ? Color(nsColor: .secondaryLabelColor) : .blue)
            }
            .buttonStyle(.borderless)
            .help(followUp.isDone ? "Mark undone" : "Mark done")
        }
        .opacity(followUp.isDone ? 0.55 : 1)
    }
}

// MARK: - WorkCard

struct WorkCard<Trailing: View>: View {
    let accent: Color
    let symbol: String
    let title: String
    let badge: String?
    let badgeColor: Color
    let subtitle: String
    let chip: String
    let chipSymbol: String
    let isDone: Bool
    @ViewBuilder var trailing: Trailing

    init(
        accent: Color,
        symbol: String,
        title: String,
        badge: String?,
        badgeColor: Color,
        subtitle: String,
        chip: String,
        chipSymbol: String,
        isDone: Bool = false,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.accent = accent
        self.symbol = symbol
        self.title = title
        self.badge = badge
        self.badgeColor = badgeColor
        self.subtitle = subtitle
        self.chip = chip
        self.chipSymbol = chipSymbol
        self.isDone = isDone
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 0) {
            accent.frame(width: 3)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: symbol)
                        .foregroundStyle(accent)
                        .frame(width: 18)
                        .font(.system(size: 13, weight: .semibold))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(isDone ? Color(nsColor: .secondaryLabelColor) : Color(nsColor: .labelColor))
                            .strikethrough(isDone, color: Color(nsColor: .secondaryLabelColor))
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    }

                    Spacer(minLength: 4)

                    VStack(alignment: .trailing, spacing: 4) {
                        if let badge {
                            Text(badge)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(badgeColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(badgeColor.opacity(0.12), in: Capsule())
                        }
                        trailing
                    }
                }

                Label(chip, systemImage: chipSymbol)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 10)
        }
        .background(
            Color(nsColor: .textBackgroundColor).opacity(0.9),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }
}

// MARK: - ApprovalCard

private struct ApprovalCard: View {
    @EnvironmentObject private var store: AgentDockStore
    let action: ProposedAction
    let costLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WorkCard(
                accent: .green,
                symbol: "bolt.badge.checkmark.fill",
                title: action.title,
                badge: action.tool.rawValue,
                badgeColor: .green,
                subtitle: action.details.isEmpty ? action.approvalPrompt : action.details,
                chip: action.target ?? action.tool.rawValue,
                chipSymbol: "arrow.up.right"
            )

            HStack {
                Button {
                    store.editingAction = action
                } label: {
                    Label("Edit first", systemImage: "pencil")
                }
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))

                Spacer()

                Button {
                    store.approve(action)
                } label: {
                    Label("Approve & Run", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
            .font(.caption)
        }
    }
}

// MARK: - ExecutionLogView

private struct ExecutionLogView: View {
    let logs: [ExecutionLog]
    @State private var isExpanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(logs) { log in
                    HStack(alignment: .top, spacing: 6) {
                        Circle()
                            .fill(log.isError ? Color.red : Color.green)
                            .frame(width: 5, height: 5)
                            .padding(.top, 3)
                        Text("[\(log.createdAt.formatted(date: .omitted, time: .standard))] \(log.message)")
                            .foregroundStyle(log.isError ? .red : Color(nsColor: .labelColor))
                    }
                }
            }
            .font(.system(.caption2, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
            .padding(.top, 6)
        } label: {
            Label("Execution Log", systemImage: "terminal")
                .font(.subheadline.weight(.semibold))
        }
    }
}

// MARK: - AgentNoteRow

private struct AgentNoteRow: View {
    let note: AgentNote

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: note.symbolName)
                .foregroundStyle(Color(nsColor: .controlAccentColor))
                .frame(width: 16)
                .font(.caption)

            VStack(alignment: .leading, spacing: 2) {
                Text(note.agentName)
                    .font(.caption.weight(.semibold))
                Text(note.summary)
                    .font(.caption)
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}
