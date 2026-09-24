import Foundation

@MainActor
enum NativeSmokeTest {
    static func run(appName: String) throws {
        let controller = AccessibilityWindowController()
        let candidates = try controller.windows().filter { $0.appName == appName }
        guard candidates.count >= 2 else {
            throw WindowControlError.unsupported("Native smoke test needs two eligible \(appName) windows.")
        }

        let target = candidates[0]
        let sibling = candidates[1]
        let targetBefore = try controller.state(of: target)
        let siblingBefore = try controller.state(of: sibling)
        var events: [AccessibilityWindowEvent] = []
        try controller.observe(target) { events.append($0) }

        try controller.move(target, by: CGPoint(x: 23, y: 31))
        let moved = try controller.state(of: target)
        guard moved.frame.origin == CGPoint(
            x: targetBefore.frame.origin.x + 23,
            y: targetBefore.frame.origin.y + 31
        ) else {
            throw WindowControlError.unsupported("Move verification failed.")
        }
        try requireUnchanged(sibling, expected: siblingBefore, controller: controller)
        print("PASS move selected window; sibling unchanged")

        try controller.resize(target)
        let resized = try controller.state(of: target)
        guard resized.frame.size != targetBefore.frame.size else {
            throw WindowControlError.unsupported("Resize verification failed.")
        }
        try requireUnchanged(sibling, expected: siblingBefore, controller: controller)
        print("PASS resize selected window; sibling unchanged")

        try controller.raiseAndFocus(sibling)
        waitForEvents()
        events.removeAll()
        try controller.raiseAndFocus(target)
        waitForEvents()
        guard try controller.isFocused(target) else {
            throw WindowControlError.unsupported("Focus verification failed.")
        }
        guard events.contains(.focused) else {
            throw WindowControlError.unsupported("Focus observation failed; events: \(eventText(events))")
        }
        print("PASS raise and focus selected window")

        try controller.minimize(target)
        waitForEvents()
        guard try controller.state(of: target).isMinimized else {
            throw WindowControlError.unsupported("Minimize verification failed.")
        }
        try controller.restore(target)
        waitForEvents()
        guard try !controller.state(of: target).isMinimized else {
            throw WindowControlError.unsupported("Restore verification failed.")
        }
        print("PASS minimize and restore selected window")

        try controller.setFullscreen(true, for: target)
        waitForEvents(seconds: 1.5)
        let fullscreenEligible = try controller.windows()
        guard !fullscreenEligible.contains(where: { CFEqual($0.element, target.element) }) else {
            throw WindowControlError.unsupported("Native-fullscreen exclusion failed.")
        }
        guard !fullscreenEligible.contains(where: { CFEqual($0.element, sibling.element) }) else {
            throw WindowControlError.unsupported("Other-Space exclusion failed.")
        }
        try controller.setFullscreen(false, for: target)
        waitForEvents(seconds: 1.5)
        print("PASS native-fullscreen and other-Space windows excluded without retrieval")

        try controller.close(target)
        waitForEvents()
        guard events.contains(.closed) else {
            throw WindowControlError.unsupported("Closure observation failed; events: \(eventText(events))")
        }
        guard events.contains(.minimized), events.contains(.restored)
        else {
            throw WindowControlError.unsupported("Minimize observation failed; events: \(eventText(events))")
        }
        print("PASS observed focus/minimize/restore/closure events: \(eventText(events))")
        try requireUnchanged(sibling, expected: siblingBefore, controller: controller)
        print("PASS same-app sibling remained usable and unchanged")
    }

    private static func requireUnchanged(
        _ window: AccessibilityWindow,
        expected: AccessibilityWindowState,
        controller: AccessibilityWindowController
    ) throws {
        guard try controller.state(of: window) == expected else {
            throw WindowControlError.unsupported("Unselected same-app window changed.")
        }
    }

    private static func waitForEvents(seconds: TimeInterval = 0.2) {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: seconds))
    }

    private static func eventText(_ events: [AccessibilityWindowEvent]) -> String {
        events.map(\.statusText).joined(separator: ", ")
    }
}
