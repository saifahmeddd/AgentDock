# AgentDock

AgentDock is a native macOS menu bar AI work assistant. Drop messy work from Slack, Gmail, PDFs, screenshots, browser pages, files, or copied text, and AgentDock turns it into clean commitments, follow-ups, source proof, and approval-gated actions.

## Setup

1. Create an OpenRouter API key at `https://openrouter.ai/`.
2. Run AgentDock:

```sh
swift run AgentDock
```

3. Open the menu bar icon, complete onboarding, and paste the API key in Settings.
4. Click Verify. The key is stored in macOS Keychain.

Default model: `x-ai/grok-3-mini`

Available models:

- `x-ai/grok-3-mini`
- `google/gemini-2.5-flash`
- `mistralai/mistral-small`
- `anthropic/claude-sonnet-4.5`

OpenRouter endpoint:

```text
https://openrouter.ai/api/v1/chat/completions
```

AgentDock sends `HTTP-Referer: agentdock-mac` and uses OpenAI-compatible JSON over `URLSession`.

## Architecture

```text
macOS Status Item
      |
      v
NSPopover + SwiftUI Panel
      |
      v
AgentDockStore (MainActor)
      |
      +--> SmartIntakeService actor
      |      +--> PDFKit text extraction
      |      +--> Vision OCR for screenshots
      |      +--> URL metadata fetch
      |      +--> source detection
      |
      +--> OpenRouterService actor
      |      +--> chat completions
      |      +--> structured JSON schema
      |      +--> retry + fallback model
      |      +--> token cost estimate
      |
      +--> SwiftData
      |      +--> Commitment
      |      +--> WaitingItem
      |      +--> SourceProof
      |
      +--> SourceArchive actor
      |      +--> ~/Library/Application Support/AgentDock/
      |
      +--> ReminderScheduler actor
      |      +--> local notifications
      |
      +--> ConnectorExecutor actor
             +--> Gmail mailto fallback
             +--> local Calendar event via EventKit
             +--> visible connector stubs
```

## Current Features

- Native AppKit status item with custom SF Symbol icon and pending badge dot
- Right-click menu: Open AgentDock, Paste & Analyze, Settings, Quit
- Option-Space global monitor for opening the panel
- Frosted `.hudWindow` panel using `NSVisualEffectView`
- Animated agent squad row
- Drag-and-drop intake with shimmer state
- OpenRouter API integration with Keychain-backed settings
- Retry logic with fallback to `x-ai/grok-3-mini`
- Estimated cost per analysis from token usage and local model price table
- Smart intake detection for email-like text, Slack URLs, PDFs, images, and browser links
- PDF text extraction with PDFKit
- Screenshot OCR with Vision
- SwiftData persistence for commitments, waiting items, and source proof
- Source proof archive in `~/Library/Application Support/AgentDock/`
- Local notifications for reminders and follow-ups
- Fuzzy deduplication for similar commitments
- Approval cards with edit sheet and execution log
- Gmail fallback via `mailto:`
- Calendar action execution through EventKit
- Dark mode through semantic `NSColor` tokens
- Reduce Motion support for panel and intake animations
- Generated `.icns` resource based on an indigo SF Symbol icon

## Known Limitations

- The project is currently a Swift Package executable, not a signed/notarized `.app` bundle. The `.icns` resource is generated, but wiring it into a distributable app target is the next packaging step.
- Slack, Notion, Linear, and Microsoft 365 connectors are visible stubs until OAuth flows are added.
- Option-Space uses an event monitor; a production global hotkey should move to a Carbon hotkey registration or hardened Accessibility-permission flow.
- Model pricing is stored locally for cost estimates. OpenRouter pricing can change, so the table should be refreshed before release.
- Calendar intent extraction is still model-driven and conservative; richer date parsing is the next improvement.
