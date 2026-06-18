import AppKit
import Foundation
import PDFKit
import UserNotifications

// MARK: - SourceArchive

actor SourceArchive {
    static let shared = SourceArchive()

    private let fileManager = FileManager.default

    func saveSourceProof(for item: IntakeItem) async -> ArchivedSourceProof {
        let proofID = UUID()
        let support = applicationSupportDirectory()
        let proofDirectory = support.appendingPathComponent("SourceProofs", isDirectory: true)
        try? fileManager.createDirectory(at: proofDirectory, withIntermediateDirectories: true)

        let rawPath = proofDirectory.appendingPathComponent("\(proofID.uuidString).txt")
        try? item.body.write(to: rawPath, atomically: true, encoding: .utf8)

        let thumbnailPath = saveThumbnail(for: item, proofID: proofID, directory: proofDirectory)

        return ArchivedSourceProof(
            id: proofID,
            rawInput: item.body,
            detectedSourceType: item.sourceKind,
            originalSource: item.originalSource,
            thumbnailPath: thumbnailPath?.path
        )
    }

    func archiveOldAnalyses(_ analyses: [AgentAnalysis]) async {
        guard !analyses.isEmpty else { return }

        let archiveDirectory = applicationSupportDirectory().appendingPathComponent("Archive", isDirectory: true)
        try? fileManager.createDirectory(at: archiveDirectory, withIntermediateDirectories: true)
        let stamp = Int(Date().timeIntervalSince1970)
        let archiveURL = archiveDirectory.appendingPathComponent("archive-\(stamp).json")

        // Persist full analysis JSON so nothing is lost — not just 4 fields.
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(analyses) {
            try? data.write(to: archiveURL, options: .atomic)
        }
    }

    func applicationSupportDirectory() -> URL {
        guard let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            // Extremely unlikely: fall back to temp directory rather than crashing.
            return fileManager.temporaryDirectory.appendingPathComponent("AgentDock", isDirectory: true)
        }
        let directory = base.appendingPathComponent("AgentDock", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func saveThumbnail(for item: IntakeItem, proofID: UUID, directory: URL) -> URL? {
        guard let attachment = item.attachments.first else { return nil }
        let thumbnailURL = directory.appendingPathComponent("\(proofID.uuidString)-thumb.tiff")

        if item.sourceKind == .screenshot,
           let image = NSImage(contentsOf: attachment),
           let tiff = image.tiffRepresentation {
            try? tiff.write(to: thumbnailURL)
            return thumbnailURL
        }

        if item.sourceKind == .pdf,
           let page = PDFDocument(url: attachment)?.page(at: 0) {
            let image = page.thumbnail(of: CGSize(width: 320, height: 420), for: .mediaBox)
            if let tiff = image.tiffRepresentation {
                try? tiff.write(to: thumbnailURL)
                return thumbnailURL
            }
        }

        return nil
    }
}

// MARK: - CrashReporter

actor CrashReporter {
    static let shared = CrashReporter()

    // Maximum character length of any single context string written to the log.
    // Keeps potentially sensitive intake content from flooding the log file.
    private let maxContextLength = 200

    func log(_ error: Error, context: String) async {
        await log(message: "[\(context)] \(error.localizedDescription)")
    }

    func log(message: String) async {
        let redacted = redact(message)
        let fileManager = FileManager.default

        guard let logsBase = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            return
        }
        let logs = logsBase
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("AgentDock", isDirectory: true)
        try? fileManager.createDirectory(at: logs, withIntermediateDirectories: true)

        let logURL = logs.appendingPathComponent("agentdock.log")
        let line = "\(ISO8601DateFormatter().string(from: .now)) \(redacted)\n"

        if fileManager.fileExists(atPath: logURL.path),
           let handle = try? FileHandle(forWritingTo: logURL) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(to: logURL, atomically: true, encoding: .utf8)
        }
    }

    // Truncates long strings and strips any API key patterns before they reach disk.
    private func redact(_ message: String) -> String {
        var result = message
        // Redact OpenRouter-style API keys (sk-or-v1-...) that may appear in error bodies.
        if let regex = try? NSRegularExpression(pattern: #"sk-or-[a-zA-Z0-9\-_]{20,}"#) {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "[REDACTED_KEY]")
        }
        // Truncate to keep intake content out of the log.
        if result.count > maxContextLength {
            let end = result.index(result.startIndex, offsetBy: maxContextLength)
            result = String(result[..<end]) + "…[truncated]"
        }
        return result
    }
}

// MARK: - ArchivedSourceProof

struct ArchivedSourceProof: Sendable {
    let id: UUID
    let rawInput: String
    let detectedSourceType: IntakeSourceKind
    let originalSource: String
    let thumbnailPath: String?
}

// MARK: - ReminderScheduler

actor ReminderScheduler {
    static let shared = ReminderScheduler()

    func requestAuthorization() async {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            await CrashReporter.shared.log(message: "notifications-skipped: not an app bundle")
            return
        }

        do {
            try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            await CrashReporter.shared.log(error, context: "notification-authorization")
        }
    }

    func schedule(title: String, body: String, date: Date?) async {
        guard let date, date > .now else { return }
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            await CrashReporter.shared.log(error, context: "schedule-reminder")
        }
    }
}

// MARK: - SnoozeOption

enum SnoozeOption: String, CaseIterable, Identifiable {
    case oneDay = "1 day"
    case threeDays = "3 days"
    case oneWeek = "1 week"

    var id: String { rawValue }

    var date: Date {
        switch self {
        case .oneDay:
            Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
        case .threeDays:
            Calendar.current.date(byAdding: .day, value: 3, to: .now) ?? .now
        case .oneWeek:
            Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now
        }
    }
}
