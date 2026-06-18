# CLAUDE.md — AgentDock

## Project Overview

AgentDock is a native macOS menu bar app (macOS 14+) that ingests messy work inputs — pasted text, PDFs, screenshots, URLs, files — and extracts structured, actionable items: commitments, follow-ups, and approval-gated proposed actions. The entire UI is a 380×580 SwiftUI popover attached to an `NSStatusItem`; there is no separate window-based app.

**Repo:** github.com/saifahmeddd/AgentDock
**Language:** Swift 100%
**Platform:** macOS 14+
**Package type:** Swift Package executable (`swift run AgentDock`) — not yet a signed `.app` bundle
**Size:** ~15 source files, ~3,200 lines of Swift

---

## How to Run

```bash
swift run AgentDock
```

After launch: click the menu bar icon → complete the 3-step onboarding → paste an OpenRouter API key in Settings → click Verify (stored in Keychain). Default model is `x-ai/grok-3-mini`.

**Important:** Running as a Swift Package executable (not a `.app` bundle) means local notifications are silently skipped — the code explicitly checks for a `.app` bundle extension before scheduling. Notifications only fire after the project is packaged as a real signed app.

---

## Tech Stack

| Layer | Technology |
|---|---|
| UI | SwiftUI + AppKit (`NSStatusItem`, `NSPopover`, `NSVisualEffectView`) |
| Persistence | SwiftData (`Commitment`, `WaitingItem`, `SourceProof`) |
| AI | OpenRouter API (`https://openrouter.ai/api/v1/chat/completions`) — OpenAI-compatible, `response_format: json_object` |
| Secrets | macOS Keychain via `Security` framework (`kSecClassGenericPassword`) |
| Document parsing | PDFKit (text extraction + thumbnailing) |
| OCR | Vision framework (`VNRecognizeTextRequest`) |
| Notifications | UserNotifications (local, no-op in SwiftPM run mode) |
| Calendar | EventKit |
| Networking | Plain `URLSession` — no third-party HTTP libraries |
| Concurrency | Swift structured concurrency — actors and `@MainActor` classes throughout |

Zero external Swift package dependencies — `Package.swift` has no `.package(url:)` entries.

---

## Architecture

```
NSStatusItem (menu bar icon)
   └─ AgentDockStatusController  — owns NSPopover, click/right-click, Option+Space global hotkey
        └─ NSPopover → NSHostingController(AgentDockPanel)   [SwiftUI]
                            │
                            ▼
                    AgentDockStore (@MainActor, ObservableObject)
                       — single orchestrator / source of truth
                       │
         ┌─────────────┼──────────────────────────────────────┐
         ▼             ▼              ▼             ▼          ▼
  SmartIntakeService  OpenRouterService  AgentPipeline  SourceArchive  ConnectorExecutor
   (actor)             (actor)            (struct,        (actor)       (actor)
   - source detection   - OpenRouter        offline          - writes raw  - mailto: Gmail
   - PDFKit extraction    chat completions   regex/keyword    text +        - EventKit Calendar
   - Vision OCR          - 3-attempt retry   fallback,        thumbnails    - stubs: Notion/
   - URL title fetch      with fallback       no network       to ~/Library/   Linear/Slack/M365
                          to grok-3-mini     needed           Application
                         - strict JSON                        Support/
                           schema                             AgentDock/
                         - cost estimation

  ReminderScheduler (actor)  — UNCalendarNotificationTrigger
  KeychainService (actor)    — Keychain CRUD for the OpenRouter API key
  AppPreferences (@MainActor)— selected model, onboarding flag, key state
  CrashReporter (actor)      — ~/Library/Logs/AgentDock/agentdock.log
                       │
                       ▼
              SwiftData ModelContext
              (Commitment / WaitingItem / SourceProof)
```

`AppEnvironment` (`@MainActor` singleton at `AppEnvironment.shared`) is the composition root — it constructs `AppPreferences`, `AgentDockStore`, and the `ModelContainer`, then wires the store to a `ModelContext`.

---

## Intake → Analysis → Persistence Pipeline

1. **Capture** — text via composer box, drag-and-drop, or right-click "Paste & Analyze" from the system pasteboard.
2. **Debounce** — `shouldAcceptDrop(signature:)` rejects duplicate drops arriving within 150ms.
3. **Smart Intake (`SmartIntakeService`)** — detects source type (Gmail, Slack, PDF, screenshot, browser link, clipboard). For URLs: fetches `<title>` and `<meta description>` via URLSession (8s timeout). For files: PDF → PDFKit; images → Vision OCR; text formats → UTF-8 read.
4. **Source Proof Archive** — raw body written to `~/Library/Application Support/AgentDock/SourceProofs/<uuid>.txt` before analysis runs. Thumbnails saved for PDFs and screenshots. `SourceProof` persisted to SwiftData immediately, independent of AI success/failure.
5. **Analysis (AI or offline fallback):**
   - **AI path:** `OpenRouterService` sends a fixed system prompt requesting strict JSON (classification, commitments, follow_ups, proposed_actions, evidence). Retries: same model × 2, then falls back to `grok-3-mini` with exponential backoff (400ms × 2^attempt). Response mapped into `AgentAnalysis`/`CommitmentDraft`/`FollowUpDraft`/`ProposedAction`.
   - **Offline fallback (`AgentPipeline`):** pure regex/keyword heuristic engine — no network required. Fires when no API key exists or all AI retries are exhausted.
6. **Persistence + Deduplication** — commitments checked against existing SwiftData rows via Levenshtein fuzzy match (0.2 normalized edit-distance threshold). Deadlines parsed by `DateParser` (understands "today/eod", "tomorrow", "week" only).
7. **Reminders** — `ReminderScheduler` schedules a `UNCalendarNotificationTrigger` per saved item (no-op in SwiftPM run mode).
8. **UI Update** — new `AgentAnalysis` prepended to `analyses`, auto-selected, "Pop" sound plays, source badge clears after 2s.
9. **Approval-gated execution (`ConnectorExecutor`)** — proposed actions never auto-run. User must tap "Approve & Run". Gmail → `mailto:` via `NSWorkspace`. Calendar → real EventKit event. Notion/Linear/Slack/M365 → log-only stubs.
10. **Archiving** — on popover close, if `analyses.count > 50`, oldest 30 are summarized (lossy: title/classification/timestamp only) to `~/Library/Application Support/AgentDock/Archive/` JSON and removed from memory.

---

## Data Model (SwiftData)

Three `@Model` classes, each with `@Attribute(.unique) var id: UUID`:

- **`Commitment`** — `title`, `owner`, `priority` (raw `String`), `deadline` (`Date?`), `reminderDate` (`Date?`), `sourceProofID` (`UUID?`), `createdAt`
- **`WaitingItem`** — `title`, `responsibleParty`, `followUpDate`, `sourceProofID`, `createdAt`
- **`SourceProof`** — `rawInput`, `detectedSourceType`, `originalSource`, `thumbnailPath`, `createdAt`

**Key design note:** `sourceProofID` is a plain `UUID` field, not a SwiftData `@Relationship`. There is no cascading delete, no join-based fetch, and no referential integrity — lookups require manual UUID matching.

The in-memory layer uses richer plain structs (`IntakeItem`, `AgentAnalysis`, `CommitmentDraft`, `FollowUpDraft`, `ProposedAction`, `EvidenceItem`, `AgentNote`, `ExecutionLog`). Only commitments, waiting items, and source proof survive a restart; all evidence, agent notes, execution logs, and cost data are ephemeral per-session.

---

## Key Source Files

| File | Responsibility |
|---|---|
| `AgentDockApp.swift` | `@main` entry point; declares only the `Settings` scene |
| `StatusItemController.swift` | `AgentDockAppDelegate`, `NSStatusItem`, `NSPopover`, Option+Space global hotkey, custom icon drawing |
| `AgentDockPanel.swift` | Main SwiftUI panel: drag-drop zone, composer, agent squad row, connector pills, analysis display, onboarding/action sheets |
| `AnalysisViews.swift` | `WorkCard`, `ApprovalCard`, `ExecutionLogView`, agent notes, source proof disclosure groups |
| `SettingsView.swift` | API key entry/verification, model picker, connector list (mostly stubs) |
| `AgentDockStore.swift` | `@MainActor` orchestrator — `ingest(_:)` pipeline entry point |
| `SmartIntakeService.swift` | Source detection, PDFKit, Vision OCR, URL metadata fetch |
| `OpenRouterService.swift` | AI API calls, retry logic, cost estimation, JSON parsing |
| `AgentPipeline.swift` | Offline regex/keyword fallback |
| `SourceArchive.swift` | Disk writes for raw text and thumbnails |
| `ConnectorExecutor.swift` | Approval execution: real Gmail/Calendar, stub Notion/Linear/Slack/M365 |
| `Models.swift` | Hardcoded model list and pricing table |
| `KeychainService.swift` | Keychain CRUD wrapper |
| `FuzzyMatcher.swift` | Levenshtein deduplication |
| `DateParser.swift` | Simple deadline parsing |

---

## AI Integration Details

- **Provider:** OpenRouter (`https://openrouter.ai/api/v1/chat/completions`)
- **Auth:** API key stored in Keychain, never logged
- **Models available:** `x-ai/grok-3-mini` (default), `google/gemini-2.5-flash`, `mistralai/mistral-small`, `anthropic/claude-sonnet-4-5`
- **Output format:** `response_format: json_object` — strict JSON schema with `classification`, `commitments`, `follow_ups`, `proposed_actions`, `evidence`
- **Retry strategy:** attempt 1 → attempt 2 (same model) → attempt 3 (grok-3-mini fallback), with 400ms × 2^attempt backoff
- **Cost estimation:** client-side, using token counts from response × hardcoded price table in `Models.swift` (will drift from live OpenRouter pricing)
- **Fallback:** `AgentPipeline` offline heuristics fire when no key exists or all retries fail

---

## Known Gaps and Risks

1. **Not distributable yet.** Only runs via `swift run AgentDock`. No app bundle, no code signing, no notarization. Notifications silently do not fire.
2. **No tests.** Zero `Tests/` directory or XCTest target. No regression safety net.
3. **Four of six connectors are stubs.** Notion, Linear, Slack, and Microsoft 365 only append a log line. Gmail is `mailto:` (not OAuth/real send). Calendar is the only fully functional connector.
4. **Fragile global hotkey.** Raw `NSEvent` global monitor for Option+Space — not a registered Carbon hotkey. Flagged in the README as needing replacement before production.
5. **Partial persistence.** Evidence, agent notes, execution logs, and cost data are in-memory only and lost on restart. The 50-item archive trim produces a lossy summary (title/classification/timestamp only).
6. **Limited date parsing.** `DateParser` only handles "today/eod", "tomorrow", and "week". AI-generated dates like "next Friday" or "March 14" fall through to +1/+2 day defaults.
7. **Hardcoded pricing table.** `Models.swift` price constants will drift from OpenRouter's live pricing.
8. **No SwiftData relationship integrity.** `sourceProofID` is a bare `UUID`; no cascade delete, no framework-enforced joins.
9. **Force-unwraps in `AppEnvironment.init()`** — `ModelContainer` creation uses `try!` and Application Support URL lookup uses `.first!`. Any failure is a hard crash.
10. **Log may capture sensitive content.** Error context strings passed to `CrashReporter` could include parts of intake bodies. Needs a privacy audit before broader distribution.
11. **No OAuth anywhere.** All "Connect a tool" UI affordances are cosmetic except Gmail (`mailto:`) and Calendar (EventKit).

---

## Suggested Enhancement Priorities

- **Package as a signed `.app`** — unlocks real notifications, enables distribution
- **Add tests** — XCTest target covering at least `AgentPipeline`, `FuzzyMatcher`, `DateParser`, and `OpenRouterService` JSON parsing
- **Harden persistence** — convert `sourceProofID` to a proper SwiftData `@Relationship`; persist full `AgentAnalysis` (evidence, agent notes, cost) across restarts
- **Implement real OAuth connectors** — start with Notion or Linear (most commonly requested)
- **Improve `DateParser`** — add support for relative weekday names, `Month Day` patterns, and `MM/DD` formats (patterns already extracted by the AI but currently wasted)
- **Replace global hotkey** — migrate from raw `NSEvent` monitor to a Carbon/Accessibility-gated registered hotkey
- **Refresh pricing table** — fetch live pricing from OpenRouter's `/models` endpoint instead of hardcoding
- **Privacy audit on `CrashReporter`** — scrub or redact intake content from error context before it reaches the log file
