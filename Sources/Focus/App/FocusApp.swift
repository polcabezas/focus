import SwiftUI
import AppKit
import FocusCore

@main
struct FocusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuContentView().environmentObject(delegate.app)
        } label: {
            MenuBarLabel().environmentObject(delegate.app)
        }
        .menuBarExtraStyle(.window)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { delegate.app.showSettings() }
                    .keyboardShortcut(",")
            }
        }
    }
}

private struct MenuBarLabel: View {
    @EnvironmentObject private var app: AppController

    var body: some View {
        Image(systemName: app.isBlockActive ? "lock.fill" : "lock.open")
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let app = AppController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        app.showSettings()
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        app.isBlockActive ? .terminateCancel : .terminateNow
    }
}
