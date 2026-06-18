import AppKit
import SwiftUI

final class AgentDockAppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: AgentDockStatusController?
    private var hotKeyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusController = AgentDockStatusController(environment: .shared)

        // Check whether Input Monitoring permission is available before installing the monitor.
        // NSEvent.addGlobalMonitorForEvents requires the Input Monitoring TCC entitlement.
        // If it's missing the monitor silently receives nothing; we surface a banner instead.
        let isTrusted = checkInputMonitoringPermission()
        Task { @MainActor in
            AppEnvironment.shared.store.hotkeyPermissionMissing = !isTrusted
        }

        if isTrusted {
            installHotKeyMonitor()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let hotKeyMonitor {
            NSEvent.removeMonitor(hotKeyMonitor)
        }
    }

    // Public so the settings/permission banner can re-check and re-install after the user grants access.
    func retryHotKeyRegistration() {
        guard hotKeyMonitor == nil else { return }
        if checkInputMonitoringPermission() {
            installHotKeyMonitor()
            Task { @MainActor in
                AppEnvironment.shared.store.hotkeyPermissionMissing = false
            }
        }
    }

    private func installHotKeyMonitor() {
        hotKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .option,
                  event.keyCode == 49 else { return }
            Task { @MainActor in
                self?.statusController?.togglePanel()
            }
        }
    }

    // AXIsProcessTrusted is an imperfect proxy here: Accessibility and Input Monitoring are
    // separate TCC categories on recent macOS, but there is no public API to check Input
    // Monitoring directly. In practice, power users who grant one often grant both, and this
    // gives us a reliable fallback signal without private API.
    private func checkInputMonitoringPermission() -> Bool {
        AXIsProcessTrusted()
    }
}

@MainActor
final class AgentDockStatusController: NSObject, NSPopoverDelegate {
    private let environment: AppEnvironment
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var cancellables: [NSObjectProtocol] = []
    private var settingsWindow: NSWindow?

    init(environment: AppEnvironment) {
        self.environment = environment
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        configureStatusItem()
        configurePopover()
        observeStore()
    }

    func togglePanel() {
        if popover.isShown {
            closePanel()
        } else {
            openPanel()
        }
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = menuBarImage(hasPending: environment.store.hasPendingItems)
        button.imagePosition = .imageOnly
        button.target = self
        button.action = #selector(statusButtonClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "AgentDock"
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.delegate = self
        popover.contentSize = NSSize(width: 380, height: 580)
        popover.contentViewController = NSHostingController(
            rootView: AgentDockPanel()
                .environmentObject(environment.store)
                .environmentObject(environment.preferences)
                .modelContainer(environment.modelContainer)
        )
    }

    private func observeStore() {
        let observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshIcon()
            }
        }
        cancellables.append(observer)
    }

    @objc private func statusButtonClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            togglePanel()
            return
        }

        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePanel()
        }
    }

    private func openPanel() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        animatePanelOpen()
    }

    private func closePanel() {
        popover.performClose(nil)
        environment.store.panelDidClose()
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Open AgentDock", action: #selector(openFromMenu), keyEquivalent: "")
        menu.addItem(withTitle: "Paste & Analyze", action: #selector(pasteAndAnalyze), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openFromMenu() { openPanel() }

    @objc private func pasteAndAnalyze() {
        let paste = NSPasteboard.general.string(forType: .string) ?? ""
        environment.store.ingestDroppedText(paste)
        openPanel()
    }

    @objc private func openSettings() {
        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let content = SettingsView()
            .environmentObject(environment.store)
            .environmentObject(environment.preferences)
            .modelContainer(environment.modelContainer)
            .frame(minWidth: 480, minHeight: 420)

        let controller = NSHostingController(rootView: content)
        let window = NSWindow(contentViewController: controller)
        window.title = "AgentDock Settings"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 480, height: 560))
        window.center()
        window.isReleasedWhenClosed = false
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() { NSApp.terminate(nil) }

    func popoverDidClose(_ notification: Notification) {
        environment.store.panelDidClose()
    }

    private func refreshIcon() {
        statusItem.button?.image = menuBarImage(hasPending: environment.store.hasPendingItems)
    }

    private func animatePanelOpen() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let window = popover.contentViewController?.view.window else { return }
        window.alphaValue = 0
        window.animator().alphaValue = 1
    }

    private func menuBarImage(hasPending: Bool) -> NSImage? {
        let size = NSSize(width: 24, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        NSImage(systemSymbolName: "square.stack.3d.up", accessibilityDescription: "AgentDock")?
            .withSymbolConfiguration(.init(pointSize: 16, weight: .semibold))?
            .draw(in: NSRect(x: 2, y: 1, width: 18, height: 16))

        if hasPending {
            NSColor.systemOrange.setFill()
            NSBezierPath(ovalIn: NSRect(x: 17, y: 11, width: 6, height: 6)).fill()
        }

        image.unlockFocus()
        image.isTemplate = !hasPending
        return image
    }
}
