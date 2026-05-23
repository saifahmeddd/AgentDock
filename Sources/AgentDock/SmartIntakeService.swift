import AppKit
import Foundation
import PDFKit
import Vision

actor SmartIntakeService {
    func itemFromText(_ text: String, preferredSource: IntakeSourceKind = .clipboard) async -> IntakeItem? {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return nil }

        var source = detectSource(in: cleanText, fallback: preferredSource)
        var metadata = detectEmailMetadata(in: cleanText)
        var badge = badge(for: source)
        var enrichedText = cleanText

        if let url = firstURL(in: cleanText) {
            if url.host?.contains("slack.com") == true {
                source = .slack
                metadata["Slack context"] = slackContext(from: url)
                badge = "Slack detected"
            } else if source == .clipboard {
                source = .browser
                badge = "Browser link detected"
            }

            if let page = try? await fetchPageMetadata(from: url) {
                metadata["Page title"] = page.title
                if let description = page.description {
                    metadata["Description"] = description
                }
                enrichedText += "\n\nPage title: \(page.title)"
                if let description = page.description {
                    enrichedText += "\nDescription: \(description)"
                }
            }
        }

        return IntakeItem(
            title: titleForText(enrichedText),
            body: enrichedText,
            sourceKind: source,
            originalSource: preferredSource.rawValue,
            sourceBadge: badge,
            metadata: metadata
        )
    }

    func itemFromFile(_ url: URL) async -> IntakeItem {
        let source = sourceKind(for: url)
        var metadata = [
            "Filename": url.lastPathComponent,
            "Path": url.path
        ]

        let body: String
        switch source {
        case .pdf:
            let extracted = extractPDFText(from: url)
            metadata["Pages"] = "\(extracted.pageCount)"
            body = extracted.text.isEmpty ? fileFallbackBody(for: url) : extracted.text
        case .screenshot:
            let text = (try? recognizeText(in: url)) ?? ""
            metadata["OCR"] = text.isEmpty ? "No text detected" : "Text detected"
            body = text.isEmpty ? fileFallbackBody(for: url) : text
        default:
            body = readableBody(for: url)
        }

        return IntakeItem(
            title: url.lastPathComponent,
            body: body,
            sourceKind: source,
            originalSource: url.path,
            attachments: [url],
            sourceBadge: badge(for: source),
            metadata: metadata
        )
    }

    private func detectSource(in text: String, fallback: IntakeSourceKind) -> IntakeSourceKind {
        let lower = text.lowercased()
        if lower.contains("from:") || lower.contains("subject:") {
            return .gmail
        }
        if lower.contains("slack.com") {
            return .slack
        }
        if firstURL(in: text) != nil {
            return .browser
        }
        return fallback
    }

    private func detectEmailMetadata(in text: String) -> [String: String] {
        var metadata: [String: String] = [:]
        for line in text.components(separatedBy: .newlines) {
            let lower = line.lowercased()
            if lower.hasPrefix("from:") {
                metadata["Sender"] = line.replacingOccurrences(of: "From:", with: "").trimmingCharacters(in: .whitespaces)
            }
            if lower.hasPrefix("subject:") {
                metadata["Subject"] = line.replacingOccurrences(of: "Subject:", with: "").trimmingCharacters(in: .whitespaces)
            }
        }
        return metadata
    }

    private func firstURL(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector.firstMatch(in: text, range: range)?.url
    }

    private func fetchPageMetadata(from url: URL) async throws -> PageMetadata {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        let (data, _) = try await URLSession.shared.data(for: request)
        let html = String(data: data, encoding: .utf8) ?? ""
        let title = firstCapture(in: html, pattern: #"<title[^>]*>(.*?)</title>"#) ?? url.absoluteString
        let description = firstCapture(in: html, pattern: #"<meta\s+name=["']description["']\s+content=["'](.*?)["']"#)
        return PageMetadata(title: title.decodedHTML, description: description?.decodedHTML)
    }

    private func extractPDFText(from url: URL) -> (text: String, pageCount: Int) {
        guard let document = PDFDocument(url: url) else {
            return ("", 0)
        }

        var text = ""
        for index in 0..<document.pageCount {
            text += document.page(at: index)?.string ?? ""
            text += "\n\n"
        }
        return (text.trimmingCharacters(in: .whitespacesAndNewlines), document.pageCount)
    }

    private func recognizeText(in url: URL) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(url: url)
        try handler.perform([request])

        return (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }

    private func readableBody(for url: URL) -> String {
        let textExtensions = ["txt", "md", "markdown", "csv", "json", "html", "rtf"]
        if textExtensions.contains(url.pathExtension.lowercased()),
           let content = try? String(contentsOf: url, encoding: .utf8) {
            return content
        }

        return fileFallbackBody(for: url)
    }

    private func fileFallbackBody(for url: URL) -> String {
        """
        Dropped file: \(url.lastPathComponent)
        Path: \(url.path)

        The original file is saved as source proof.
        """
    }

    private func sourceKind(for url: URL) -> IntakeSourceKind {
        switch url.pathExtension.lowercased() {
        case "pdf": .pdf
        case "png", "jpg", "jpeg", "heic", "tiff": .screenshot
        case "html", "webloc": .browser
        default: .file
        }
    }

    private func titleForText(_ text: String) -> String {
        let firstLine = text.components(separatedBy: .newlines).first ?? text
        guard firstLine.count > 64 else { return firstLine }
        let end = firstLine.index(firstLine.startIndex, offsetBy: 64)
        return String(firstLine[..<end]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private func slackContext(from url: URL) -> String {
        let pieces = url.pathComponents.filter { $0 != "/" }
        if let channel = pieces.first(where: { $0.hasPrefix("C") || $0.hasPrefix("D") }) {
            return channel.hasPrefix("D") ? "DM \(channel)" : "#\(channel)"
        }
        return url.host ?? "Slack"
    }

    private func badge(for source: IntakeSourceKind) -> String {
        switch source {
        case .gmail: "Gmail detected"
        case .slack: "Slack detected"
        case .pdf: "PDF detected"
        case .screenshot: "Screenshot OCR"
        case .browser: "Browser page detected"
        default: "\(source.rawValue) detected"
        }
    }

    private func firstCapture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let swiftRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[swiftRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct PageMetadata {
    let title: String
    let description: String?
}

private extension String {
    var decodedHTML: String {
        replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}
