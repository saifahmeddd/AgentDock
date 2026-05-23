import AppKit
import Foundation
import PDFKit
import UserNotifications

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
        let archiveURL = archiveDirectory.appendingPathComponent("archive-\(Int(Date().timeIntervalSince1970)).json")

        let payload = analyses.map {
            [
                "id": $0.id.uuidString,
                "title": $0.intake.title,
                "classification": $0.classification.rawValue,
                "createdAt": ISO8601DateFormatter().string(from: $0.intake.createdAt)
            ]
        }

        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]) {
            try? data.write(to: archiveURL, options: .atomic)
        }
    }

    private func applicationSupportDirectory() -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
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

actor CrashReporter {
    static let shared = CrashReporter()

    func log(_ error: Error, context: String) async {
        await log(message: "[\(context)] \(error.localizedDescription)")
    }

    func log(message: String) async {
        let fileManager = FileManager.default
        let logs = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("AgentDock", isDirectory: true)
        try? fileManager.createDirectory(at: logs, withIntermediateDirectories: true)

        let logURL = logs.appendingPathComponent("agentdock.log")
        let line = "\(ISO8601DateFormatter().string(from: .now)) \(message)\n"

        if fileManager.fileExists(atPath: logURL.path),
           let handle = try? FileHandle(forWritingTo: logURL) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(to: logURL, atomically: true, encoding: .utf8)
        }
    }
}

struct ArchivedSourceProof: Sendable {
    let id: UUID
    let rawInput: String
    let detectedSourceType: IntakeSourceKind
    let originalSource: String
    let thumbnailPath: String?
}

actor ReminderScheduler {
    static let shared = ReminderScheduler()

    func requestAuthorization() async {
        do {
            try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            await CrashReporter.shared.log(error, context: "notification-authorization")
        }
    }

    func schedule(title: String, body: String, date: Date?) async {
        guard let date, date > .now else { return }
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
