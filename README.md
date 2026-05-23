# AgentDock

AgentDock is a native macOS menu bar AI work assistant. It opens from the menu bar, accepts dropped work, and turns messy input into commitments, follow-ups, source proof, and approval-ready actions.

## Current Build

- Native SwiftUI macOS app using `MenuBarExtra`
- Compact menu bar window
- Drag-and-drop intake for text, file URLs, links, PDFs, and screenshots
- Manual paste composer with source selection
- Local agent pipeline for:
  - intake capture
  - task and promise detection
  - deadline signals
  - waiting/follow-up detection
  - approval-ready tool actions
  - source proof preservation

## Run

```sh
swift run AgentDock
```

After launch, use the AgentDock icon in the macOS menu bar.

## Shape Of The App

```text
Sources/AgentDock/
  AgentDockApp.swift      macOS app entry and menu bar scene
  AgentDockPanel.swift    compact menu bar UI and drop handling
  AgentDockStore.swift    app state and ingestion flow
  AgentPipeline.swift     local agent analysis heuristics
  Models.swift            core product data models
  AnalysisViews.swift     commitments, follow-ups, approvals, proof
  SettingsView.swift      basic settings surface
```

## Next Product Layer

The approval flow is intentionally present before external execution. The next layer should add connector implementations for Gmail, Calendar, Notion, Linear, Slack, and Microsoft 365 behind `ProposedAction`, so AgentDock can draft or execute only after the user approves.
