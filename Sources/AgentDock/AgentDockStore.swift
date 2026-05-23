import Foundation

@MainActor
final class AgentDockStore: ObservableObject {
    @Published var intakeItems: [IntakeItem] = []
    @Published var analyses: [AgentAnalysis] = []
    @Published var selectedAnalysisID: UUID?
    @Published var draftText = ""
    @Published var selectedSource: IntakeSourceKind = .clipboard
    @Published var isProcessing = false

    private let pipeline = AgentPipeline()

    var selectedAnalysis: AgentAnalysis? {
        guard let selectedAnalysisID else { return analyses.first }
        return analyses.first(where: { $0.id == selectedAnalysisID }) ?? analyses.first
    }

    func ingestDraftText() {
        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let item = IntakeItem(
            title: titleForText(text),
            body: text,
            sourceKind: selectedSource,
            originalSource: selectedSource.rawValue
        )
        ingest(item)
        draftText = ""
    }

    func ingestDroppedText(_ text: String) {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return }

        ingest(
            IntakeItem(
                title: titleForText(cleanText),
                body: cleanText,
                sourceKind: .clipboard,
                originalSource: "Dropped text"
            )
        )
    }

    func ingestFiles(_ urls: [URL]) {
        for url in urls {
            let body = readableBody(for: url)
            let item = IntakeItem(
                title: url.lastPathComponent,
                body: body,
                sourceKind: sourceKind(for: url),
                originalSource: url.path,
                attachments: [url]
            )
            ingest(item)
        }
    }

    func approve(_ action: ProposedAction) {
        guard let index = analyses.firstIndex(where: { analysis in
            analysis.proposedActions.contains(where: { $0.id == action.id })
        }) else { return }

        analyses[index].notes.append(
            AgentNote(
                agentName: "Approval Agent",
                summary: "Approved '\(action.title)' for \(action.tool.rawValue). Connector execution is ready to wire next.",
                symbolName: "checkmark.seal"
            )
        )
    }

    func clearAll() {
        intakeItems.removeAll()
        analyses.removeAll()
        selectedAnalysisID = nil
    }

    private func ingest(_ item: IntakeItem) {
        isProcessing = true
        intakeItems.insert(item, at: 0)
        let analysis = pipeline.analyze(item)
        analyses.insert(analysis, at: 0)
        selectedAnalysisID = analysis.id
        isProcessing = false
    }

    private func titleForText(_ text: String) -> String {
        let firstLine = text.components(separatedBy: .newlines).first ?? text
        guard firstLine.count > 64 else { return firstLine }
        let end = firstLine.index(firstLine.startIndex, offsetBy: 64)
        return String(firstLine[..<end]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private func sourceKind(for url: URL) -> IntakeSourceKind {
        switch url.pathExtension.lowercased() {
        case "pdf": .pdf
        case "png", "jpg", "jpeg", "heic", "tiff": .screenshot
        case "html", "webloc": .browser
        default: .file
        }
    }

    private func readableBody(for url: URL) -> String {
        let textExtensions = ["txt", "md", "markdown", "csv", "json", "html", "rtf"]
        if textExtensions.contains(url.pathExtension.lowercased()),
           let content = try? String(contentsOf: url, encoding: .utf8) {
            return content
        }

        return """
        Dropped file: \(url.lastPathComponent)
        Path: \(url.path)

        The original file is saved as source proof. Text extraction/OCR for this file type can be connected next.
        """
    }
}
