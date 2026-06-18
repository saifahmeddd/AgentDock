import Foundation

// Reads a .env file from the current working directory (where `swift run` is invoked)
// and syncs the values into Keychain so they persist across relaunches.
// Supported keys:
//   NIM_API_KEY        — NVIDIA NIM API key (nvapi-…)
//   NOTION_TOKEN       — Notion integration token (secret_…)
//   NOTION_PAGE_ID     — Notion parent page ID or URL
//   LINEAR_API_KEY     — Linear personal API key
//   LINEAR_TEAM_ID     — Linear team UUID

enum DotEnvLoader {
    static func loadAndSync() async {
        let env = parse()
        guard !env.isEmpty else { return }

        let map: [(String, KeychainService.Credential)] = [
            ("NIM_API_KEY",     .nimAPIKey),
            ("NOTION_TOKEN",    .notionToken),
            ("NOTION_PAGE_ID",  .notionPageID),
            ("LINEAR_API_KEY",  .linearAPIKey),
            ("LINEAR_TEAM_ID",  .linearTeamID),
        ]

        for (key, credential) in map {
            guard let value = env[key], !value.isEmpty else { continue }
            try? await KeychainService.shared.save(value, for: credential)
        }
    }

    static func parse() -> [String: String] {
        // 1. Try .env in the current working directory (swift run invocation path)
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let candidates = [
            cwd.appendingPathComponent(".env"),
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".config/agentdock/.env")
        ]

        var result: [String: String] = [:]

        // Also pick up values already set in the process environment
        let processEnv = ProcessInfo.processInfo.environment
        for (key, value) in processEnv where knownKeys.contains(key) {
            result[key] = value
        }

        // File overrides process env (file is more explicit)
        for url in candidates {
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                for line in text.components(separatedBy: .newlines) {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
                    let parts = trimmed.split(separator: "=", maxSplits: 1)
                    guard parts.count == 2 else { continue }
                    let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
                    var value = String(parts[1]).trimmingCharacters(in: .whitespaces)
                    // Strip surrounding quotes
                    if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
                       (value.hasPrefix("'") && value.hasSuffix("'")) {
                        value = String(value.dropFirst().dropLast())
                    }
                    if !key.isEmpty { result[key] = value }
                }
                break // use the first file found
            }
        }

        return result
    }

    private static let knownKeys: Set<String> = [
        "NIM_API_KEY", "NOTION_TOKEN", "NOTION_PAGE_ID", "LINEAR_API_KEY", "LINEAR_TEAM_ID"
    ]
}
