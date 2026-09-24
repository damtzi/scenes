import AppKit

if let smokeIndex = CommandLine.arguments.firstIndex(of: "--smoke") {
    guard CommandLine.arguments.indices.contains(smokeIndex + 1) else {
        print("Usage: Scenes --smoke <app-name>")
        exit(2)
    }
    do {
        try NativeSmokeTest.run(appName: CommandLine.arguments[smokeIndex + 1])
    } catch {
        print("FAIL \(error.localizedDescription)")
        exit(1)
    }
} else if CommandLine.arguments.contains("--diagnose") {
    let controller = AccessibilityWindowController()
    print("Accessibility trusted: \(controller.isTrusted)")
    do {
        let windows = try controller.windows()
        print("Eligible windows: \(windows.count)")
        for window in windows {
            print("\(window.processIdentifier)\t\(window.appName)\t\(window.menuTitle)\tminimized=\(window.isMinimized)")
        }
    } catch {
        print("Window enumeration failed: \(error.localizedDescription)")
        exit(1)
    }
} else {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.accessory)
    application.run()
}
