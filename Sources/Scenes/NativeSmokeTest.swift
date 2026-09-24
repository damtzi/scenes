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
        var events: [String] = []
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

        try controller.raiseAndFocus(target)
        waitForEvents()
        guard try controller.isFocused(target) else {
            throw WindowControlError.unsupported("Focus verification failed.")
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

        try controller.close(target)
        waitForEvents()
        guard events.contains("Observed: selected window closed") else {
            throw WindowControlError.unsupported("Closure observation failed; events: \(events)")
        }
        guard events.contains("Observed: selected window minimized"),
              events.contains("Observed: selected window restored")
        else {
            throw WindowControlError.unsupported("Minimize observation failed; events: \(events)")
        }
        print("PASS observed focus/minimize/restore/closure events: \(events.joined(separator: ", "))")
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

    private static func waitForEvents() {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))
    }
}
