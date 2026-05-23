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
                        .lineLimit(2)
                    Label(analysis.classification.rawValue, systemImage: analysis.intake.sourceKind.symbolName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(analysis.intake.createdAt, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !analysis.commitments.isEmpty {
                SectionBlock(title: "Commitments", symbolName: "checkmark.circle") {
                    ForEach(analysis.commitments) { commitment in
                        CommitmentRow(commitment: commitment)
                    }
                }
            }

            if !analysis.followUps.isEmpty {
                SectionBlock(title: "Waiting", symbolName: "clock.arrow.circlepath") {
                    ForEach(analysis.followUps) { followUp in
                        FollowUpRow(followUp: followUp)
                    }
                }
            }

            if !analysis.proposedActions.isEmpty {
                SectionBlock(title: "Approval", symbolName: "bolt.badge.checkmark") {
                    ForEach(analysis.proposedActions) { action in
                        ActionRow(action: action) {
                            store.approve(action)
                        }
                    }
                }
            }

            SectionBlock(title: "Agent Squad", symbolName: "person.3.fill") {
                VStack(spacing: 8) {
                    ForEach(analysis.notes) { note in
                        AgentNoteRow(note: note)
                    }
                }
            }

            SectionBlock(title: "Source Proof", symbolName: "paperclip") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(analysis.evidence) { evidence in
                        HStack(alignment: .firstTextBaseline) {
                            Text(evidence.label)
                                .foregroundStyle(.secondary)
                                .frame(width: 104, alignment: .leading)
                            Text(evidence.value)
                                .lineLimit(3)
                                .textSelection(.enabled)
                            Spacer(minLength: 0)
                        }
                        .font(.caption)
                    }

                    Text(analysis.intake.body)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(5)
                        .textSelection(.enabled)
                        .padding(.top, 4)
                }
            }
        }
    }
}

private struct SectionBlock<Content: View>: View {
    let title: String
    let symbolName: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbolName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

private struct CommitmentRow: View {
    let commitment: Commitment

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(commitment.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                Spacer()
                PriorityBadge(priority: commitment.priority)
            }

            MetadataLine(symbolName: "person", text: commitment.owner)
            MetadataLine(symbolName: "bell", text: commitment.reminder)
            if let deadline = commitment.deadline {
                MetadataLine(symbolName: "calendar", text: deadline)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .textBackgroundColor))
        )
    }
}

private struct FollowUpRow: View {
    let followUp: FollowUp

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(followUp.title)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
            MetadataLine(symbolName: "person.crop.circle.badge.questionmark", text: followUp.responsibleParty)
            MetadataLine(symbolName: "calendar.badge.clock", text: followUp.checkBack)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .textBackgroundColor))
        )
    }
}

private struct ActionRow: View {
    let action: ProposedAction
    let onApprove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(action.title)
                        .font(.subheadline.weight(.medium))
                    Text(action.tool.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: onApprove) {
                    Image(systemName: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .help("Approve")
            }

            Text(action.approvalPrompt)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .textBackgroundColor))
        )
    }
}

private struct AgentNoteRow: View {
    let note: AgentNote

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: note.symbolName)
                .foregroundStyle(.teal)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(note.agentName)
                    .font(.caption.weight(.semibold))
                Text(note.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}

private struct MetadataLine: View {
    let symbolName: String
    let text: String

    var body: some View {
        Label(text, systemImage: symbolName)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
    }
}

private struct PriorityBadge: View {
    let priority: Priority

    var color: Color {
        switch priority {
        case .low: .gray
        case .normal: .blue
        case .high: .orange
        case .urgent: .red
        }
    }

    var body: some View {
        Text(priority.rawValue)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(color.opacity(0.12))
            )
    }
}
