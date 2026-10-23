import AppKit
import FocusCore

/// Removes Focus, its data and its background item. The app then quits; launchd's job is booted out a second later.
@MainActor
enum Uninstaller {
    static func uninstall() {
        let fm = FileManager.default
        do {
            // Trash the app first. If that fails, nothing has been removed yet.
            try fm.trashItem(at: Bundle.main.bundleURL, resultingItemURL: nil)
        } catch {
            NSAlert(error: error).runModal()
            return
        }
        try? fm.removeItem(at: LaunchAgent.plist)
        try? fm.removeItem(at: Store.directory)
        let library = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library")
        for path in ["Preferences/\(LaunchAgent.label).plist", "Caches/\(LaunchAgent.label)",
                     "Saved Application State/\(LaunchAgent.label).savedState", "WebKit/\(LaunchAgent.label)",
                     "Application Scripts/\(LaunchAgent.label)", "Containers/\(LaunchAgent.label)"] {
            try? fm.removeItem(at: library.appendingPathComponent(path))
        }
        let storages = library.appendingPathComponent("HTTPStorages")
        for url in (try? fm.contentsOfDirectory(at: storages, includingPropertiesForKeys: nil)) ?? []
            where url.lastPathComponent.hasPrefix(LaunchAgent.label) {
            try? fm.removeItem(at: url)
        }
        // A job cannot boot itself out before it exits, so a detached shell does it after exit(0).
        // exit(0) also stops KeepAlive from restarting the app.
        let job = Process()
        job.executableURL = URL(fileURLWithPath: "/bin/sh")
        job.arguments = ["-c", "sleep 1; launchctl bootout gui/\(getuid())/\(LaunchAgent.label); "
                         + "tccutil reset All \(LaunchAgent.label)"]
        try? job.run()
        exit(0)
    }
}
