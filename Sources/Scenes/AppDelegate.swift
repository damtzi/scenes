import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = AccessibilityWindowController()
    private let menu = NSMenu()
    private var statusItem: NSStatusItem!
    private var windows: [UUID: AccessibilityWindow] = [:]
    private var selectedWindow: AccessibilityWindow?
    private var statusText = "Starting…"
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: "Scenes")
        statusItem.menu = menu
        refresh()
        if !controller.isTrusted {
            controller.requestPermission()
        }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermissionIfNeeded() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionTimer?.invalidate()
        controller.stopObserving()
    }

    @objc private func refresh() {
        do {
            let available = try controller.windows()
            windows = Dictionary(uniqueKeysWithValues: available.map { ($0.id, $0) })
            if let selectedWindow,
               !available.contains(where: { CFEqual($0.element, selectedWindow.element) }) {
                self.selectedWindow = nil
                controller.stopObserving()
            }
            statusText = "Found \(available.count) eligible window\(available.count == 1 ? "" : "s")"
        } catch {
            windows = [:]
            selectedWindow = nil
            statusText = error.localizedDescription
        }
        rebuildMenu()
    }

    @objc private func requestPermission() {
        controller.requestPermission()
        statusText = "Permission requested; approve Scenes in System Settings."
        rebuildMenu()
    }

    @objc private func openSettings() {
        controller.openAccessibilitySettings()
    }

    @objc private func selectWindow(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID, let window = windows[id] else { return }
        selectedWindow = window
        do {
            try controller.observe(window) { [weak self] event in
                self?.statusText = event.statusText
                self?.rebuildMenu()
            }
            statusText = "Selected \(window.appName) — \(window.menuTitle)"
        } catch {
            statusText = error.localizedDescription
        }
        rebuildMenu()
    }

    @objc private func moveSelected() { perform("Moved selected window") { try controller.move($0) } }
    @objc private func resizeSelected() { perform("Resized selected window") { try controller.resize($0) } }
    @objc private func raiseSelected() { perform("Raised and focused selected window") { try controller.raiseAndFocus($0) } }
    @objc private func restoreSelected() { perform("Restored selected window") { try controller.restore($0) } }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func perform(_ success: String, operation: (AccessibilityWindow) throws -> Void) {
        guard let selectedWindow else {
            statusText = "Select a window first."
            rebuildMenu()
            return
        }
        do {
            try operation(selectedWindow)
            statusText = success
        } catch {
            statusText = error.localizedDescription
        }
        rebuildMenu()
    }

    private func refreshPermissionIfNeeded() {
        let denied = windows.isEmpty && statusText.contains("permission")
        if controller.isTrusted == denied { refresh() }
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        let status = NSMenuItem(title: statusText, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        if !controller.isTrusted {
            menu.addItem(item("Request Accessibility Permission", action: #selector(requestPermission)))
            menu.addItem(item("Open Accessibility Settings…", action: #selector(openSettings)))
            menu.addItem(.separator())
            let explanation = NSMenuItem(title: "Scenes needs Accessibility to inspect and control windows.", action: nil, keyEquivalent: "")
            explanation.isEnabled = false
            menu.addItem(explanation)
        } else {
            addWindowItems()
            menu.addItem(.separator())
            menu.addItem(item("Move +40 px", action: #selector(moveSelected), enabled: selectedWindow != nil))
            menu.addItem(item("Resize to 70% of Display", action: #selector(resizeSelected), enabled: selectedWindow != nil))
            menu.addItem(item("Raise and Focus", action: #selector(raiseSelected), enabled: selectedWindow != nil))
            menu.addItem(item("Restore If Minimized", action: #selector(restoreSelected), enabled: selectedWindow != nil))
            menu.addItem(.separator())
            menu.addItem(item("Refresh Windows", action: #selector(refresh), key: "r"))
        }

        menu.addItem(.separator())
        menu.addItem(item("Quit Scenes", action: #selector(quit), key: "q"))
    }

    private func addWindowItems() {
        let grouped = Dictionary(grouping: windows.values, by: \.appName)
        for appName in grouped.keys.sorted() {
            let appItem = NSMenuItem(title: appName, action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            let appWindows = grouped[appName]!.sorted { $0.menuTitle < $1.menuTitle }
            var duplicateCounts: [String: Int] = [:]
            for window in appWindows {
                duplicateCounts[window.menuTitle, default: 0] += 1
                let duplicateIndex = duplicateCounts[window.menuTitle]!
                let totalDuplicates = appWindows.count { $0.menuTitle == window.menuTitle }
                let suffix = totalDuplicates > 1 ? " (\(duplicateIndex))" : ""
                let minimized = window.isMinimized ? " [minimized]" : ""
                let windowItem = item("\(window.menuTitle)\(suffix)\(minimized)", action: #selector(selectWindow))
                windowItem.representedObject = window.id
                windowItem.state = selectedWindow.map { CFEqual($0.element, window.element) } == true ? .on : .off
                submenu.addItem(windowItem)
            }
            appItem.submenu = submenu
            menu.addItem(appItem)
        }
        if grouped.isEmpty {
            let empty = NSMenuItem(title: "No eligible windows on the current Space", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
    }

    private func item(_ title: String, action: Selector, key: String = "", enabled: Bool = true) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.isEnabled = enabled
        return item
    }
}
