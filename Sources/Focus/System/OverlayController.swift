import AppKit
import SwiftUI
import FocusCore

enum OverlayKind: Hashable {
    case blocked, emergency, settings, browserWarning
}

private final class OverlayPanel: NSPanel {
    override func cancelOperation(_ sender: Any?) {
        close()
    }
}

@MainActor
final class OverlayController: NSObject, NSWindowDelegate {
    private unowned let app: AppController
    private var windows: [OverlayKind: NSWindow] = [:]

    init(app: AppController) {
        self.app = app
        super.init()
    }

    func showBlocked(target: String, kind: TargetKind) {
        present(.blocked, BlockedView(target: target, kind: kind, onClose: { [weak self] in self?.close(.blocked) }))
    }

    func showBrowserWarning(appName: String, reason: String, deadline: Date?) {
        present(.browserWarning, BrowserWarningView(appName: appName, reason: reason, deadline: deadline,
                                                    onClose: { [weak self] in self?.close(.browserWarning) }))
    }

    func showEmergency() {
        if let window = windows[.emergency] { show(window); return }
        present(.emergency, EmergencyView(onClose: { [weak self] in self?.close(.emergency) }))
    }

    func showSettings() {
        NSApp.setActivationPolicy(.regular)
        if let window = windows[.settings] { show(window); return }
        let host = NSHostingController(rootView: SettingsView().environmentObject(app))
        let window = NSWindow(contentViewController: host)
        window.title = "Focus Settings"
        window.setContentSize(NSSize(width: 620, height: 520))
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.delegate = self
        window.center()
        windows[.settings] = window
        show(window)
    }

    func close(_ kind: OverlayKind) {
        windows[kind]?.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let kind = windows.first(where: { $0.value === window })?.key else { return }
        windows[kind] = nil
        if kind == .emergency { app.cancelEmergency() }
        if kind == .settings {
            DispatchQueue.main.async { NSApp.setActivationPolicy(.accessory) }
        }
    }

    private func present<V: View>(_ kind: OverlayKind, _ view: V) {
        close(kind)
        let host = NSHostingController(rootView: view.environmentObject(app))
        host.sizingOptions = [.preferredContentSize]
        let panel = OverlayPanel(contentRect: .zero, styleMask: [.titled, .fullSizeContentView, .closable],
                                 backing: .buffered, defer: false)
        panel.delegate = self
        panel.contentViewController = host
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isRestorable = false
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }
        panel.center()
        windows[kind] = panel
        show(panel)
    }

    private func show(_ window: NSWindow) {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
