import AppKit
import ApplicationServices

struct AccessibilityWindow: Identifiable {
    let id = UUID()
    let appName: String
    let processIdentifier: pid_t
    let title: String
    let element: AXUIElement
    let isMinimized: Bool

    var menuTitle: String {
        title.isEmpty ? "Untitled" : title
    }
}

struct AccessibilityWindowState: Equatable {
    let frame: CGRect
    let isMinimized: Bool
}

enum WindowControlError: LocalizedError {
    case accessibilityDenied
    case attribute(String, AXError)
    case noScreen
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .accessibilityDenied:
            "Accessibility permission is not granted."
        case let .attribute(name, error):
            "\(name) failed (AX error \(error.rawValue))."
        case .noScreen:
            "No display is available."
        case let .unsupported(reason):
            reason
        }
    }
}

@MainActor
final class AccessibilityWindowController {
    typealias StatusHandler = (String) -> Void

    private var appObservers: [pid_t: AXObserver] = [:]
    private var observedWindow: AXUIElement?
    private var statusHandler: StatusHandler?

    var isTrusted: Bool { AXIsProcessTrusted() }

    func requestPermission() {
        let options = [
            "AXTrustedCheckOptionPrompt": true,
        ] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    func windows() throws -> [AccessibilityWindow] {
        guard isTrusted else { throw WindowControlError.accessibilityDenied }

        let currentSpaceWindows = currentSpaceWindowSignatures()
        var results: [AccessibilityWindow] = []

        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            let application = AXUIElementCreateApplication(app.processIdentifier)
            guard let elements: [AXUIElement] = value(of: kAXWindowsAttribute, from: application) else {
                continue
            }

            for element in elements {
                guard value(of: kAXRoleAttribute, from: element) as String? == kAXWindowRole,
                      value(of: "AXFullScreen", from: element) as Bool? != true
                else { continue }

                let minimized = value(of: kAXMinimizedAttribute, from: element) as Bool? ?? false
                let frame = frame(of: element)
                let signature = frame.map { WindowSignature(pid: app.processIdentifier, frame: $0) }

                // Public APIs expose current-Space membership only for visible windows.
                // Keep minimized windows selectable so restoration can be proven; the UI
                // labels this limitation rather than pretending their Space is known.
                guard minimized || signature.map(currentSpaceWindows.contains) == true else { continue }

                results.append(AccessibilityWindow(
                    appName: app.localizedName ?? app.bundleIdentifier ?? "Unknown App",
                    processIdentifier: app.processIdentifier,
                    title: value(of: kAXTitleAttribute, from: element) as String? ?? "",
                    element: element,
                    isMinimized: minimized
                ))
            }
        }

        return results.sorted {
            ($0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending)
                || ($0.appName == $1.appName && $0.menuTitle.localizedCaseInsensitiveCompare($1.menuTitle) == .orderedAscending)
        }
    }

    func move(_ window: AccessibilityWindow, by offset: CGPoint = CGPoint(x: 40, y: 40)) throws {
        try requireTrusted()
        guard var position: CGPoint = value(of: kAXPositionAttribute, from: window.element) else {
            throw WindowControlError.unsupported("This window does not expose a movable position.")
        }
        position.x += offset.x
        position.y += offset.y
        try set(point: position, attribute: kAXPositionAttribute, on: window.element)
    }

    func resize(_ window: AccessibilityWindow) throws {
        try requireTrusted()
        guard let screen = screen(containing: window.element) ?? NSScreen.main else {
            throw WindowControlError.noScreen
        }
        let target = WindowGeometry.centeredFrame(in: screen.visibleFrame)
        try set(size: target.size, attribute: kAXSizeAttribute, on: window.element)
    }

    func raiseAndFocus(_ window: AccessibilityWindow) throws {
        try requireTrusted()
        let app = AXUIElementCreateApplication(window.processIdentifier)
        try set(boolean: true, attribute: kAXFrontmostAttribute, on: app)
        try set(boolean: true, attribute: kAXMainAttribute, on: window.element)
        let result = AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
        guard result == .success else { throw WindowControlError.attribute("Raise", result) }
    }

    func restore(_ window: AccessibilityWindow) throws {
        try requireTrusted()
        try set(boolean: false, attribute: kAXMinimizedAttribute, on: window.element)
    }

    func minimize(_ window: AccessibilityWindow) throws {
        try requireTrusted()
        try set(boolean: true, attribute: kAXMinimizedAttribute, on: window.element)
    }

    func close(_ window: AccessibilityWindow) throws {
        try requireTrusted()
        guard let closeButton: AXUIElement = value(of: kAXCloseButtonAttribute, from: window.element) else {
            throw WindowControlError.unsupported("This window does not expose a close button.")
        }
        let result = AXUIElementPerformAction(closeButton, kAXPressAction as CFString)
        guard result == .success else { throw WindowControlError.attribute("Close", result) }
    }

    func state(of window: AccessibilityWindow) throws -> AccessibilityWindowState {
        try requireTrusted()
        guard let frame = frame(of: window.element) else {
            throw WindowControlError.unsupported("This window does not expose position and size.")
        }
        return AccessibilityWindowState(
            frame: frame,
            isMinimized: value(of: kAXMinimizedAttribute, from: window.element) as Bool? ?? false
        )
    }

    func isFocused(_ window: AccessibilityWindow) throws -> Bool {
        try requireTrusted()
        let app = AXUIElementCreateApplication(window.processIdentifier)
        let focused: AXUIElement? = value(of: kAXFocusedWindowAttribute, from: app)
        return focused.map { CFEqual($0, window.element) } ?? false
    }

    func observe(_ window: AccessibilityWindow, status: @escaping StatusHandler) throws {
        stopObserving()
        statusHandler = status
        observedWindow = window.element

        var observer: AXObserver?
        let result = AXObserverCreate(window.processIdentifier, Self.observerCallback, &observer)
        guard result == .success, let observer else {
            throw WindowControlError.attribute("Create observer", result)
        }

        let context = Unmanaged.passUnretained(self).toOpaque()
        let app = AXUIElementCreateApplication(window.processIdentifier)
        let registrations: [(AXUIElement, String)] = [
            (app, kAXFocusedWindowChangedNotification),
            (window.element, kAXUIElementDestroyedNotification),
            (window.element, kAXWindowMiniaturizedNotification),
            (window.element, kAXWindowDeminiaturizedNotification),
        ]
        for (element, notification) in registrations {
            let error = AXObserverAddNotification(observer, element, notification as CFString, context)
            guard error == .success || error == .notificationAlreadyRegistered else {
                throw WindowControlError.attribute("Observe \(notification)", error)
            }
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        appObservers[window.processIdentifier] = observer
    }

    func stopObserving() {
        for observer in appObservers.values {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        appObservers.removeAll()
        observedWindow = nil
        statusHandler = nil
    }

    private static let observerCallback: AXObserverCallback = { _, element, notification, context in
        guard let context else { return }
        let controller = Unmanaged<AccessibilityWindowController>.fromOpaque(context).takeUnretainedValue()
        let event = notification as String
        let eventElement = SendableAXElement(value: element)
        MainActor.assumeIsolated {
            switch event {
            case kAXUIElementDestroyedNotification:
                controller.statusHandler?("Observed: selected window closed")
            case kAXWindowMiniaturizedNotification:
                controller.statusHandler?("Observed: selected window minimized")
            case kAXWindowDeminiaturizedNotification:
                controller.statusHandler?("Observed: selected window restored")
            case kAXFocusedWindowChangedNotification:
                let focusedElement: AXUIElement? = controller.value(
                    of: kAXFocusedWindowAttribute,
                    from: eventElement.value
                )
                let focused = CFEqual(eventElement.value, controller.observedWindow)
                    || (focusedElement.map { CFEqual($0, controller.observedWindow) } ?? false)
                controller.statusHandler?(focused ? "Observed: selected window focused" : "Observed: focus changed")
            default:
                break
            }
        }
    }

    private func requireTrusted() throws {
        guard isTrusted else { throw WindowControlError.accessibilityDenied }
    }

    private func screen(containing element: AXUIElement) -> NSScreen? {
        guard let windowFrame = frame(of: element) else { return nil }
        return NSScreen.screens.max { lhs, rhs in
            lhs.frame.intersection(windowFrame).area < rhs.frame.intersection(windowFrame).area
        }
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        guard let position: CGPoint = value(of: kAXPositionAttribute, from: element),
              let size: CGSize = value(of: kAXSizeAttribute, from: element)
        else { return nil }
        return CGRect(origin: position, size: size)
    }

    private func value<T>(of attribute: String, from element: AXUIElement) -> T? {
        var rawValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &rawValue) == .success,
              let rawValue
        else { return nil }

        if CFGetTypeID(rawValue) == AXValueGetTypeID() {
            let axValue = unsafeDowncast(rawValue, to: AXValue.self)
            var point = CGPoint.zero
            if AXValueGetType(axValue) == .cgPoint, AXValueGetValue(axValue, .cgPoint, &point) {
                return point as? T
            }
            var size = CGSize.zero
            if AXValueGetType(axValue) == .cgSize, AXValueGetValue(axValue, .cgSize, &size) {
                return size as? T
            }
        }
        return rawValue as? T
    }

    private func set(point: CGPoint, attribute: String, on element: AXUIElement) throws {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else {
            throw WindowControlError.unsupported("Could not encode a window position.")
        }
        try set(value: value, attribute: attribute, on: element)
    }

    private func set(size: CGSize, attribute: String, on element: AXUIElement) throws {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else {
            throw WindowControlError.unsupported("Could not encode a window size.")
        }
        try set(value: value, attribute: attribute, on: element)
    }

    private func set(boolean: Bool, attribute: String, on element: AXUIElement) throws {
        try set(value: boolean as CFBoolean, attribute: attribute, on: element)
    }

    private func set(value: CFTypeRef, attribute: String, on element: AXUIElement) throws {
        var settable = DarwinBoolean(false)
        let check = AXUIElementIsAttributeSettable(element, attribute as CFString, &settable)
        guard check == .success, settable.boolValue else {
            throw WindowControlError.unsupported("\(attribute) is not supported by this window.")
        }
        let result = AXUIElementSetAttributeValue(element, attribute as CFString, value)
        guard result == .success else { throw WindowControlError.attribute(attribute, result) }
    }

    private func currentSpaceWindowSignatures() -> Set<WindowSignature> {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[CFString: Any]] else {
            return []
        }
        return Set(windows.compactMap { info in
            guard let pid = info[kCGWindowOwnerPID] as? pid_t,
                  let bounds = info[kCGWindowBounds] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"],
                  let width = bounds["Width"], let height = bounds["Height"]
            else { return nil }
            return WindowSignature(pid: pid, frame: CGRect(x: x, y: y, width: width, height: height))
        })
    }
}

private struct WindowSignature: Hashable {
    let pid: pid_t
    let x: Int
    let y: Int
    let width: Int
    let height: Int

    init(pid: pid_t, frame: CGRect) {
        self.pid = pid
        x = Int(frame.origin.x.rounded())
        y = Int(frame.origin.y.rounded())
        width = Int(frame.width.rounded())
        height = Int(frame.height.rounded())
    }
}

private struct SendableAXElement: @unchecked Sendable {
    let value: AXUIElement
}

private extension CGRect {
    var area: CGFloat { max(0, width) * max(0, height) }
}
