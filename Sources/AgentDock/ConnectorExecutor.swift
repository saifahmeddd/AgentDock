import AppKit
import EventKit
import Foundation

actor ConnectorExecutor {
    static let shared = ConnectorExecutor()

    func execute(_ action: ProposedAction) async -> [ExecutionLog] {
        var logs = [
            ExecutionLog(message: "Preparing \(action.tool.rawValue) connector...")
        ]

        do {
            switch action.tool {
            case .gmail:
                try await openMailTo(for: action)
                logs.append(ExecutionLog(message: "Opened mail draft via mailto fallback."))
            case .calendar:
                try await createCalendarEvent(for: action)
                logs.append(ExecutionLog(message: "Created local calendar event."))
            case .notion, .linear, .slack, .microsoft365:
                logs.append(ExecutionLog(message: "\(action.tool.rawValue) connector stub ready. OAuth connection comes next."))
            }
            logs.append(ExecutionLog(message: "Execution completed."))
        } catch {
            logs.append(ExecutionLog(message: error.localizedDescription, isError: true))
            await CrashReporter.shared.log(error, context: "connector-execution")
        }

        return logs
    }

    @MainActor
    private func openMailTo(for action: ProposedAction) throws {
        let target = action.target?.contains("@") == true ? action.target! : ""
        let subject = action.title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? action.title
        let body = action.details.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? action.details
        guard let url = URL(string: "mailto:\(target)?subject=\(subject)&body=\(body)") else {
            throw ConnectorError.invalidURL
        }
        NSWorkspace.shared.open(url)
    }

    private func createCalendarEvent(for action: ProposedAction) async throws {
        let store = EKEventStore()

        if #available(macOS 14.0, *) {
            try await store.requestFullAccessToEvents()
        } else {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                store.requestAccess(to: .event) { granted, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if granted {
                        continuation.resume(returning: ())
                    } else {
                        continuation.resume(throwing: ConnectorError.calendarAccessDenied)
                    }
                }
            }
        }

        let event = EKEvent(eventStore: store)
        event.title = action.title
        event.notes = action.details.isEmpty ? action.sourceProof : action.details
        event.calendar = store.defaultCalendarForNewEvents
        event.startDate = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
        event.endDate = Calendar.current.date(byAdding: .hour, value: 1, to: event.startDate) ?? event.startDate
        try store.save(event, span: .thisEvent)
    }
}

enum ConnectorError: LocalizedError {
    case invalidURL
    case calendarAccessDenied

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Could not create a mail draft URL."
        case .calendarAccessDenied: "Calendar access was not granted."
        }
    }
}
