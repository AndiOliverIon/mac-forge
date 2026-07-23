import AppKit
import Foundation

guard
    CommandLine.arguments.count == 2,
    let cycleSeconds = TimeInterval(CommandLine.arguments[1]),
    cycleSeconds > 0
else {
    fputs("Error: Invalid cycle duration.\n", stderr)
    exit(2)
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

print("Captured \(apps.count) open apps:")
for (index, app) in apps.enumerated() {
    let name = app.localizedName ?? "PID \(app.processIdentifier)"
    let suffix = index == currentIndex ? " (current)" : ""
    print("  - \(name)\(suffix)")
}
print("Cycling every \(cycleLabel) seconds. Press Ctrl+C to stop.")

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
        app.activate(options: [])
    }

    nextIndex = (nextIndex + 1) % apps.count
}
