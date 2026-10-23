import SwiftUI
import AppKit
import FocusCore

struct BlockedView: View {
    @EnvironmentObject var app: AppController
    let target: String
    let kind: TargetKind
    let onClose: () -> Void

    var body: some View {
        content.overlayPanel()
    }

    /// App targets arrive as a bundle id; show the app's name like the system does.
    private var displayName: String {
        guard kind == .app else { return target }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target) else { return target }
        return FileManager.default.displayName(atPath: url.path)
    }

    private var content: some View {
        let block = app.activeBlocks.first
        let end = app.activeBlocks.map(\.end).max() ?? app.now
        let message = block.map { "Blocked by \($0.mode.name) until \(Theme.clock(end))." }
            ?? "Blocked until \(Theme.clock(end))."
        return VStack(spacing: 24) {
            OverlayHeader(symbol: "hand.raised.fill", tint: .red,
                          title: "\(displayName) is blocked", message: message)
            OverlayTimer(seconds: end.timeIntervalSince(app.now))
                .foregroundStyle(Color.red)
            OverlayActions {
                EmptyView()
            } trailing: {
                Button("Back to Work", action: onClose)
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}
