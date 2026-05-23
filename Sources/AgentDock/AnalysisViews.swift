import SwiftUI

struct AnalysisDetailView: View {
    @EnvironmentObject private var store: AgentDockStore
    let analysis: AgentAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(analysis.intake.title)
                        .font(.headline)
                        .foregroundStyle(Color(nsColor: .labelColor))
                        .lineLimit(2)
                    Label(analysis.classification.rawValue, systemImage: analysis.intake.sourceKind.symbolName)
                        .font(.caption)
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                }

                Spacer()

                Text(analysis.intake.createdAt, style: .time)
                    .font(.caption)
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            }

            ForEach(analysis.commitments) { commitment in
                WorkCard(
                    accent: .orange,
                    symbol: "checkmark.circle.fill",
                    title: commitment.title,
                    subtitle: commitment.owner,
                    chip: commitment.deadline ?? commitment.reminder,
                    source: analysis.intake.sourceKind.rawValue,
                    footer: analysis.costLabel
                ) {
                    Menu {
                        ForEach(SnoozeOption.allCases) { option in
                            Button(option.rawValue) {
                                store.snoozeCommitment(commitment, option: option)
                            }
                        }
                    } label: {
                        Image(systemName: "bell.badge")
                    }
                    .menuStyle(.borderlessButton)
                    .help("Snooze")
                }
            }

            ForEach(analysis.followUps) { followUp in
                WorkCard(
                    accent: .blue,
                    symbol: "clock.arrow.circlepath",
                    title: followUp.title,
                    subtitle: followUp.responsibleParty,
                    chip: followUp.checkBack,
                    source: analysis.intake.sourceKind.rawValue,
                    footer: analysis.costLabel
                )
            }

            ForEach(analysis.proposedActions) { action in
                ApprovalCard(action: action, footer: analysis.costLabel)
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
        }
    }
}

private struct WorkCard<Trailing: View>: View {
    let accent: Color
    let symbol: String
    let title: String
    let subtitle: String
    let chip: String
    let source: String
    let footer: String
    @ViewBuilder var trailing: Trailing

    init(
        accent: Color,
        symbol: String,
        title: String,
        subtitle: String,
        chip: String,
        source: String,
        footer: String,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.accent = accent
        self.symbol = symbol
        self.title = title
        self.subtitle = subtitle
        self.chip = chip
        self.source = source
        self.footer = footer
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 0) {
            accent
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: symbol)
                        .foregroundStyle(accent)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color(nsColor: .labelColor))
                            .lineLimit(3)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    }

                    Spacer()
                    trailing
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                }

                HStack(spacing: 6) {
                    Chip(text: chip, symbol: "calendar")
                    Chip(text: source, symbol: "paperclip")
                }

                Text("Estimated cost: \(footer)")
                    .font(.caption2)
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
            }
            .padding(11)
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.92), in: RoundedRectangle(cornerRadius: 8))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
    }
}

private struct ApprovalCard: View {
    @EnvironmentObject private var store: AgentDockStore
    let action: ProposedAction
    let footer: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WorkCard(
                accent: .green,
                symbol: "bolt.badge.checkmark.fill",
                title: action.title,
                subtitle: action.details.isEmpty ? action.approvalPrompt : action.details,
                chip: action.tool.rawValue,
                source: action.target ?? "Approval required",
                footer: footer
            )

            HStack {
                Button {
                    store.editingAction = action
                } label: {
                    Label("Edit first", systemImage: "pencil")
                }

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

private struct ExecutionLogView: View {
    let logs: [ExecutionLog]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Execution Log", systemImage: "terminal")
                .font(.subheadline.weight(.semibold))
            VStack(alignment: .leading, spacing: 5) {
                ForEach(logs) { log in
                    Text("[\(log.createdAt.formatted(date: .omitted, time: .standard))] \(log.message)")
                        .foregroundStyle(log.isError ? .red : Color(nsColor: .labelColor))
                }
            }
            .font(.system(.caption, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

private struct Chip: View {
    let text: String
    let symbol: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption2.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
    }
}

private struct AgentNoteRow: View {
    let note: AgentNote

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: note.symbolName)
                .foregroundStyle(Color(nsColor: .controlAccentColor))
                .frame(width: 18)

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
