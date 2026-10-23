import SwiftUI
import FocusCore

struct BrowserWarningView: View {
    @EnvironmentObject var app: AppController
    let appName: String
    let reason: String
    let deadline: Date?
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            if let deadline {
                OverlayHeader(symbol: "exclamationmark.triangle.fill", tint: .orange,
                              title: "\(appName) is disconnected", message: reason)
                OverlayTimer(seconds: deadline.timeIntervalSince(app.now))
            } else {
                OverlayHeader(symbol: "exclamationmark.triangle.fill", tint: .orange,
                              title: "\(appName) can't be used during a session", message: reason)
            }
            OverlayActions {
                EmptyView()
            } trailing: {
                Button("OK", action: onClose)
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .overlayPanel()
    }
}
