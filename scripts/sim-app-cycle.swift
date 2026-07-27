import AppKit
import Foundation

func frontWindowBounds(for processIdentifier: pid_t) -> CGRect? {
    guard let windows = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements],
        kCGNullWindowID
    ) as? [[String: Any]] else {
        return nil
    }

    for window in windows {
        guard
            let ownerPID = window[kCGWindowOwnerPID as String] as? NSNumber,
            ownerPID.int32Value == processIdentifier,
            let layer = window[kCGWindowLayer as String] as? NSNumber,
            layer.intValue == 0,
            let boundsDictionary = window[kCGWindowBounds as String] as? NSDictionary,
            let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
            bounds.width > 1,
            bounds.height > 1
        else {
            continue
        }

        return bounds
    }

    return nil
}

let mouseEventSource = CGEventSource(stateID: .hidSystemState)

func postMouseMove(to point: CGPoint) -> Bool {
    guard let event = CGEvent(
        mouseEventSource: mouseEventSource,
        mouseType: .mouseMoved,
        mouseCursorPosition: point,
        mouseButton: .left
    ) else {
        return false
    }

    event.post(tap: .cghidEventTap)
    return true
}

func simulateMouseMovement(for app: NSRunningApplication) -> Bool {
    guard
        let bounds = frontWindowBounds(for: app.processIdentifier),
        let currentEvent = CGEvent(source: nil)
    else {
        return false
    }

    let originalPoint = currentEvent.location
    let targetPoint = CGPoint(x: bounds.midX, y: bounds.midY)
    let jitterPoint = CGPoint(
        x: min(targetPoint.x + 4, bounds.maxX - 1),
        y: targetPoint.y
    )

    defer {
        _ = postMouseMove(to: originalPoint)
    }

    guard postMouseMove(to: targetPoint) else {
        return false
    }

    Thread.sleep(forTimeInterval: 0.06)
    guard postMouseMove(to: jitterPoint) else {
        return false
    }

    Thread.sleep(forTimeInterval: 0.06)
    return true
}

guard
    CommandLine.arguments.count == 2,
    let cycleSeconds = TimeInterval(CommandLine.arguments[1]),
    cycleSeconds > 0
else {
    fputs("Error: Invalid cycle duration.\n", stderr)
    exit(2)
}

guard CGPreflightPostEventAccess() else {
    _ = CGRequestPostEventAccess()
    fputs(
        "Error: sim requires Accessibility permission to simulate mouse movement. "
            + "Allow your terminal in System Settings > Privacy & Security > Accessibility, "
            + "then run sim again.\n",
        stderr
    )
    exit(1)
}

let apps = NSWorkspace.shared.runningApplications.filter {
    $0.activationPolicy == .regular && !$0.isTerminated
}

guard apps.count >= 2 else {
    fputs("Error: At least two open apps are required; found \(apps.count).\n", stderr)
    exit(1)
}

let currentIndex = apps.firstIndex(where: \.isActive) ?? (apps.count - 1)
let cycleLabel = CommandLine.arguments[1]
var available = Array(repeating: true, count: apps.count)
var availableCount = apps.count
var nextIndex = (currentIndex + 1) % apps.count
var interactionWarnings = Set<pid_t>()

print("Captured \(apps.count) open apps:")
for (index, app) in apps.enumerated() {
    let name = app.localizedName ?? "PID \(app.processIdentifier)"
    let suffix = index == currentIndex ? " (current)" : ""
    print("  - \(name)\(suffix)")
}
print("Cycling with mouse movement every \(cycleLabel) seconds. Press Ctrl+C to stop.")

while true {
    Thread.sleep(forTimeInterval: cycleSeconds)

    while !available[nextIndex] {
        nextIndex = (nextIndex + 1) % apps.count
    }

    let app = apps[nextIndex]
    if app.isTerminated {
        available[nextIndex] = false
        availableCount -= 1

        if availableCount < 2 {
            fputs("Error: Fewer than two apps from the captured collection are still open.\n", stderr)
            exit(1)
        }
    } else {
        let activated = app.activate(options: [])
        Thread.sleep(forTimeInterval: 0.2)

        if activated && !simulateMouseMovement(for: app),
            interactionWarnings.insert(app.processIdentifier).inserted
        {
            let name = app.localizedName ?? "PID \(app.processIdentifier)"
            fputs("Warning: Could not simulate mouse movement for \(name).\n", stderr)
        }
    }

    nextIndex = (nextIndex + 1) % apps.count
}
