import SwiftUI
import AppKit
import FocusCore

struct MenuContentView: View {
    @EnvironmentObject var app: AppController

    var body: some View {
        VStack(spacing: 10) {
            if !app.bridgeListening || app.lastError != nil {
                errorLines
            }
            statusModule
            if !app.installedBrowsers.isEmpty {
                browsersModule
            }
            if !app.isBlockActive {
                SessionStarter()
            }
            footer
        }
        .padding(14)
        .frame(width: 300)
        .animation(.default, value: app.isBlockActive)
    }

    // MARK: Errors

    private var errorLines: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !app.bridgeListening {
                Text("The browser bridge isn't running on port 47823. Retrying.")
            }
            if let error = app.lastError {
                Text(error)
            }
        }
        .font(.caption)
        .foregroundStyle(.red)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    // MARK: Status

    private var statusModule: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: statusSymbol)
                    .font(.system(size: 18, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(statusTint)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(statusTint.opacity(0.15)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusTitle)
                        .font(.headline)
                    Text(statusDetail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            if let end = blockEnd {
                Text(Theme.timeLeft(end.timeIntervalSince(app.now)))
                    .font(.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.red)
                    .contentTransition(.numericText())
            }
        }
        .menuModule()
    }

    private var blockEnd: Date? {
        app.isBlockActive ? app.activeBlocks.map(\.end).max() : nil
    }

    private var statusSymbol: String {
        app.isBlockActive ? "hand.raised.fill" : "checkmark.circle"
    }

    private var statusTint: Color {
        app.isBlockActive ? .red : .secondary
    }

    private var statusTitle: String {
        app.isBlockActive ? "Blocking" : "Not Blocking"
    }

    private var statusDetail: String {
        if let block = app.activeBlocks.first, let end = blockEnd {
            return "\(block.mode.name) · ends \(Theme.clock(end))"
        }
        return "No session or schedule is active."
    }

    // MARK: Browsers

    private var browsersModule: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Extensions")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(app.installedBrowsers) { browser in
                let status = extensionStatus(browser.bundleID)
                HStack(spacing: 8) {
                    Text(browser.displayName)
                    Spacer(minLength: 8)
                    Circle()
                        .fill(status.dot)
                        .frame(width: 8, height: 8)
                    Text(status.text)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .menuModule()
    }

    // Connected = seen in the last 45s; idle = seen earlier since launch; otherwise never seen.
    private func extensionStatus(_ bundleID: String) -> (text: String, dot: Color) {
        if app.connectedBrowsers.contains(bundleID) { return ("Connected", .green) }
        if app.browserSeen[bundleID] != nil { return ("Idle", .secondary) }
        return ("Not Connected", .orange)
    }

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 2) {
            Divider()
                .padding(.bottom, 4)
            if app.canEmergencyExit {
                MenuRow(title: "Emergency Exit…") { app.showEmergency() }
            }
            MenuRow(title: "Settings…", hint: "⌘,", key: ",") { app.showSettings() }
            MenuRow(title: "Quit Focus", hint: "⌘Q", key: "q", disabled: app.isBlockActive) {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}

/// A native-menu style row: plain, full width, left aligned, highlighted on hover.
private struct MenuRow: View {
    let title: String
    var hint: String?
    var key: KeyEquivalent?
    var disabled = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                Spacer(minLength: 12)
                if let hint {
                    Text(hint).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect(cornerRadius: 6))
            .background(isHovered && !disabled ? Color.primary.opacity(0.08) : Color.clear, in: .rect(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { isHovered = $0 }
        .optionalKeyboardShortcut(key)
    }
}

extension View {
    /// A Control Center style module: quaternary fill, 12pt radius, 12pt padding.
    func menuModule() -> some View {
        self
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.fill.quaternary, in: .rect(cornerRadius: 12))
    }
}

private extension View {
    @ViewBuilder
    func optionalKeyboardShortcut(_ key: KeyEquivalent?) -> some View {
        if let key {
            self.keyboardShortcut(key, modifiers: .command)
        } else {
            self
        }
    }
}
