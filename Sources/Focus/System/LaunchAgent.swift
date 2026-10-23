import AppKit
import FocusCore

/// Runs Focus at login through a LaunchAgent that points at this copy of the app. Opening the app from a disk
/// image or a translocated download offers to move it into Applications first.
@MainActor
enum LaunchAgent {
    static let label = "com.pol.focus"
    static let plist = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents/\(label).plist")

    /// Called once at launch. Shows the move prompt, hands the app over to launchd and exits, or does nothing.
    static func start() {
        // Only a real app bundle registers. A `swift run` binary must never make itself a login item.
        guard Bundle.main.bundleIdentifier == label, let exec = Bundle.main.executablePath else { return }
        if exec.hasPrefix("/Volumes/") || exec.contains("/AppTranslocation/") {
            promptToMove()
        } else if register(exec) {
            exit(0) // launchd's copy is running now. Exit 0, so KeepAlive does not restart this one.
        }
    }

    /// Makes the agent start this executable. Returns true when launchd took over from this process.
    private static func register(_ exec: String) -> Bool {
        let current = NSDictionary(contentsOf: plist)
        let pointsHere = (current?["ProgramArguments"] as? [String])?.first == exec
        let otherRunning = NSRunningApplication.runningApplications(withBundleIdentifier: label)
            .contains { $0.processIdentifier != getpid() }
        if pointsHere && !otherRunning { return false }
        if !pointsHere && !writePlist(exec) { return false }
        // Launched by launchd: this process already is the agent's job. The new file applies at next login.
        if ProcessInfo.processInfo.environment["XPC_SERVICE_NAME"] == label { return false }
        // Bootout also stops an older instance that is still running, so only this copy remains.
        run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(label)"])
        return run("/bin/launchctl", ["bootstrap", "gui/\(getuid())", plist.path]) == 0
    }

    private static func writePlist(_ exec: String) -> Bool {
        let agent: [String: Any] = [
            "Label": label,
            "ProgramArguments": [exec],
            "RunAtLoad": true,
            "KeepAlive": ["SuccessfulExit": false],
            "ProcessType": "Interactive",
        ]
        do {
            try FileManager.default.createDirectory(at: plist.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: agent, format: .xml, options: 0)
            try data.write(to: plist, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private static func promptToMove() {
        let alert = NSAlert()
        alert.messageText = "Move Focus to Applications"
        alert.informativeText = "Focus needs to be in your Applications folder to run in the background."
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Quit")
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { exit(0) }
        do {
            let copy = try copyToApplications()
            run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", copy.path])
            NSWorkspace.shared.openApplication(at: copy, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                if error == nil { exit(0) }
            }
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    /// Copies this bundle to /Applications, or to ~/Applications when /Applications is not writable.
    private static func copyToApplications() throws -> URL {
        let fm = FileManager.default
        var folder = URL(filePath: "/Applications")
        if !fm.isWritableFile(atPath: folder.path) {
            folder = fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let destination = folder.appendingPathComponent("Focus.app")
        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
        try fm.copyItem(at: Bundle.main.bundleURL, to: destination)
        return destination
    }

    @discardableResult
    private static func run(_ tool: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        do {
            try process.run()
        } catch {
            return -1
        }
        process.waitUntilExit()
        return process.terminationStatus
    }
}
