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
                logs.append(ExecutionLog(message: "Opened mail draft via mailto."))
            case .calendar:
                try await createCalendarEvent(for: action)
                logs.append(ExecutionLog(message: "Created calendar event."))
            case .notion:
                let url = try await createNotionPage(for: action)
                logs.append(ExecutionLog(message: "Created Notion page: \(url)"))
            case .linear:
                let url = try await createLinearIssue(for: action)
                logs.append(ExecutionLog(message: "Created Linear issue: \(url)"))
            case .slack, .microsoft365:
                logs.append(ExecutionLog(message: "\(action.tool.rawValue) connector not yet implemented."))
            }
            logs.append(ExecutionLog(message: "Execution completed."))
        } catch {
            logs.append(ExecutionLog(message: error.localizedDescription, isError: true))
            await CrashReporter.shared.log(error, context: "connector-execution")
        }

        return logs
    }

    // MARK: - Gmail

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

    // MARK: - Calendar

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

    // MARK: - Notion

    private func createNotionPage(for action: ProposedAction) async throws -> String {
        guard let token = try await KeychainService.shared.load(.notionToken), !token.isEmpty else {
            throw ConnectorError.missingCredential("Notion integration token not set. Add it in Settings.")
        }
        guard let pageID = try await KeychainService.shared.load(.notionPageID), !pageID.isEmpty else {
            throw ConnectorError.missingCredential("Notion parent page ID not set. Add it in Settings.")
        }

        let cleanPageID = pageID.replacingOccurrences(of: "-", with: "")
        let url = URL(string: "https://api.notion.com/v1/pages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("2022-06-28", forHTTPHeaderField: "Notion-Version")

        let body: [String: Any] = [
            "parent": ["page_id": cleanPageID],
            "properties": [
                "title": [
                    "title": [["text": ["content": action.title]]]
                ]
            ],
            "children": [
                [
                    "object": "block",
                    "type": "paragraph",
                    "paragraph": [
                        "rich_text": [["type": "text", "text": ["content": action.details.isEmpty ? action.approvalPrompt : action.details]]]
                    ]
                ]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "unknown"
            throw ConnectorError.apiError("Notion returned error: \(message)")
        }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let pageURLStr = json["url"] as? String {
            return pageURLStr
        }
        return "https://notion.so"
    }

    // MARK: - Linear

    private func createLinearIssue(for action: ProposedAction) async throws -> String {
        guard let apiKey = try await KeychainService.shared.load(.linearAPIKey), !apiKey.isEmpty else {
            throw ConnectorError.missingCredential("Linear API key not set. Add it in Settings.")
        }
        guard let teamID = try await KeychainService.shared.load(.linearTeamID), !teamID.isEmpty else {
            throw ConnectorError.missingCredential("Linear team ID not set. Add it in Settings.")
        }

        let mutation = """
        mutation IssueCreate($input: IssueCreateInput!) {
          issueCreate(input: $input) {
            success
            issue { url }
          }
        }
        """
        let variables: [String: Any] = [
            "input": [
                "teamId": teamID,
                "title": action.title,
                "description": action.details.isEmpty ? action.approvalPrompt : action.details
            ]
        ]
        let graphqlBody: [String: Any] = ["query": mutation, "variables": variables]

        let url = URL(string: "https://api.linear.app/graphql")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(apiKey, forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: graphqlBody)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "unknown"
            throw ConnectorError.apiError("Linear returned error: \(message)")
        }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let dataObj = json["data"] as? [String: Any],
           let issueCreate = dataObj["issueCreate"] as? [String: Any],
           let issue = issueCreate["issue"] as? [String: Any],
           let issueURL = issue["url"] as? String {
            return issueURL
        }
        return "https://linear.app"
    }
}

enum ConnectorError: LocalizedError {
    case invalidURL
    case calendarAccessDenied
    case missingCredential(String)
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Could not create a mail draft URL."
        case .calendarAccessDenied: "Calendar access was not granted."
        case .missingCredential(let msg): msg
        case .apiError(let msg): msg
        }
    }
}
