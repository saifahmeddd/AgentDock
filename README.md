# AgentDock

A native macOS menu bar AI action layer. Drop messy work — Slack threads, Gmail snippets, PDFs, screenshots, browser links, files, or copied text — and AgentDock extracts clean commitments, follow-ups, and approval-gated AI actions.

macOS 14+ · Swift · Zero third-party dependencies

---

## Features

- **Drop anything.** Drag files or paste text into the panel. Smart intake detects source type (email, Slack, PDF, screenshot, browser link, clipboard) automatically.
- **AI analysis.** OpenRouter API with structured JSON output. 3-attempt retry with fallback to `grok-3-mini`. Falls back to local regex/keyword heuristics if the key is missing or all retries fail — a banner shows when this happens.
- **Full persistence.** All analyses (commitments, follow-ups, proposed actions, evidence, agent notes, cost) survive restarts via SwiftData. Nothing is lost when the app closes.
- **Richer date parsing.** Parses natural-language deadlines: `"next Friday"`, `"March 14"`, `"7/4"`, `"tomorrow"`, weekday names, ISO 8601 dates.
- **Approval-gated actions.** Proposed actions never auto-execute. User must tap "Approve & Run". Gmail opens a `mailto:` draft. Calendar creates a real EventKit event.
- **Real connector status.** Gmail and Calendar are ready via system APIs (shown as "Ready"). Notion, Linear, Slack, and Microsoft 365 show "Not connected" with a link to the relevant developer portal.
- **Hotkey.** Option+Space opens the panel. A banner appears with a direct link to System Settings if Accessibility permission is missing.
- **Source proof archive.** Raw intake body and thumbnails saved to `~/Library/Application Support/AgentDock/SourceProofs/` before analysis runs.
- **Dark mode and Reduce Motion** support throughout.
- **36 unit tests** covering `AgentPipeline`, `FuzzyMatcher`, `DateParser`, and OpenRouter JSON decoding.

---

## Setup

### Option 1 — quick prototype run (no notifications)

```bash
swift run AgentDock
```

Click the menu bar icon → complete onboarding → open Settings → paste your OpenRouter key → click Verify.

> Notifications do **not** fire in SwiftPM run mode. Package as a `.app` bundle (Option 2) to enable them.

### Option 2 — real .app bundle (notifications enabled)

```bash
./scripts/package-app.sh
open build/AgentDock.app
```

This builds a release binary, assembles the `.app` bundle, embeds `AgentDock.icns`, writes `Info.plist`, and ad-hoc signs. Runs on **this Mac only**; other machines need a signed build — see [Signing and Notarization](#signing-and-notarization).

### Run tests

```bash
swift test
```

36 tests, zero failures.

---

## Models

| Model | Cost (input / output per M tokens) | Latency |
|---|---|---|
| `x-ai/grok-3-mini` | $0.30 / $0.50 | Fast (default) |
| `google/gemini-2.5-flash` | $0.30 / $2.50 | Fast |
| `mistralai/mistral-small` | $0.10 / $0.30 | Fast, cheapest |
| `anthropic/claude-sonnet-4.5` | $3.00 / $15.00 | Moderate, highest quality |

Cost estimates are client-side approximations. Check [openrouter.ai/models](https://openrouter.ai/models) for live pricing.

---

## Architecture

```
NSStatusItem (menu bar icon)
      │
      └─ AgentDockStatusController (NSPopover, hotkey, permission check)
             │
             └─ AgentDockPanel (SwiftUI)
                    │
                    └─ AgentDockStore (@MainActor)
                           │
             ┌─────────────┼──────────────────────────────────────┐
             ▼             ▼             ▼             ▼           ▼
   SmartIntakeService  OpenRouterService  AgentPipeline  SourceArchive  ConnectorExecutor
   (actor)             (actor)           (struct)       (actor)        (actor)
   source detection    chat completions  offline        disk writes    Gmail mailto:
   PDFKit/OCR/URL      retry+fallback    regex/keyword  SourceProofs/  EventKit calendar
                       cost estimate     no network     thumbnails     stubs: Notion/Linear/
                       JSON decoding                                   Slack/M365
```

**Persistence:**
- SwiftData → `Commitment`, `WaitingItem`, `SourceProof`, `StoredAnalysis` (full JSON)
- `~/Library/Application Support/AgentDock/` → raw text + thumbnails + archives
- `~/Library/Logs/AgentDock/agentdock.log` → redacted operational log (API keys stripped, content truncated)

---

## Connectors

| Connector | Status | Notes |
|---|---|---|
| Gmail | Ready (system) | `mailto:` draft via `NSWorkspace` |
| Calendar | Ready (system) | Real EventKit event with permission prompt |
| Notion | Not connected | Register at notion.so/my-integrations |
| Linear | Not connected | Create an API key at linear.app/settings/api |
| Slack | Not connected | Register an app at api.slack.com/apps |
| Microsoft 365 | Not connected | Register in Azure portal |

Tapping "Not connected" in Settings opens the relevant developer portal. OAuth flows are the next milestone.

---

## Known Limitations

1. **Ad-hoc signing only.** Without a paid Apple Developer account, the `.app` runs on this Mac only. See [Signing and Notarization](#signing-and-notarization).
2. **Four connectors are stubs.** Notion, Linear, Slack, Microsoft 365 need OAuth app registration before they can execute actions.
3. **Global hotkey needs Accessibility permission.** A banner guides the user to grant it.
4. **Hardcoded model pricing.** Cost estimates are local approximations that will drift as OpenRouter prices change.
5. **`sourceProofID` is a bare `UUID`**, not a `@Relationship`. Cascade delete not enforced by SwiftData.
6. **Notifications only fire from a `.app` bundle.** `swift run` silently skips them by design.

---

## Signing and Notarization

For distribution to others or the App Store:

1. **Enroll in Apple Developer Program** ($99/year) at [developer.apple.com](https://developer.apple.com).
2. **Create a Developer ID certificate** in Xcode → Settings → Accounts.
3. **Re-run the script** with your identity:
   ```bash
   ./scripts/package-app.sh "Developer ID Application: Your Name (TEAMID)"
   ```
4. **Notarize:**
   ```bash
   xcrun notarytool submit build/AgentDock.app \
       --apple-id your@email.com \
       --team-id YOURTEAMID \
       --password "app-specific-password" \
       --wait
   xcrun stapler staple build/AgentDock.app
   ```

---

## Development

```bash
swift run AgentDock          # prototype run (no notifications)
swift test                    # 36 tests
./scripts/package-app.sh      # build distributable .app (ad-hoc signed)
open ~/Library/Application\ Support/AgentDock/SourceProofs/
tail -f ~/Library/Logs/AgentDock/agentdock.log
```

Key source files:

| File | Responsibility |
|---|---|
| `StatusItemController.swift` | `NSStatusItem`, `NSPopover`, hotkey, permission check |
| `AgentDockPanel.swift` | Main SwiftUI panel, drop zone, connector pills |
| `AnalysisViews.swift` | `WorkCard`, `ApprovalCard`, execution log, agent notes |
| `SettingsView.swift` | API key, model picker, connector status |
| `AgentDockStore.swift` | `@MainActor` orchestrator, `DateParser`, `FuzzyMatcher`, full persistence |
| `SmartIntakeService.swift` | Source detection, PDFKit, Vision OCR, URL metadata |
| `OpenRouterService.swift` | AI calls, retry, cost estimation, JSON decoding |
| `AgentPipeline.swift` | Offline regex/keyword fallback |
| `AppSupportServices.swift` | `SourceArchive`, `CrashReporter`, `ReminderScheduler` |
| `ConnectorExecutor.swift` | Gmail `mailto:`, EventKit calendar, connector stubs |
| `Models.swift` | Enums, Codable structs, SwiftData `@Model`s |
| `AppEnvironment.swift` | Composition root, `ModelContainer` (graceful fallback on init failure) |
| `AppPreferences.swift` | Model selection, API key state, connector auth state |
