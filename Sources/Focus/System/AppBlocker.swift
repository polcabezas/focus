import AppKit
import FocusCore

@MainActor
final class AppBlocker {
    private unowned let app: AppController
    private var frontApp: (bid: String, since: Date)?
    private var lastShown: [String: Date] = [:]
    private var missingSince: [String: Date] = [:]
    private var closing: Set<String> = []
    private var tokens: [NSObjectProtocol] = []
    private let protected: Set<String> = ["com.pol.focus", "com.apple.finder"]
    private let heartbeatGrace: TimeInterval = 45
    private let warningPeriod: TimeInterval = 20

    init(app: AppController) {
        self.app = app
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didActivateApplicationNotification] {
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.sweep() }
            })
        }
    }

    func sweep() {
        let now = app.now
        let running = NSWorkspace.shared.runningApplications
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if front != frontApp?.bid { frontApp = front.map { (bid: $0, since: now) } }
        let runningIDs = Set(running.compactMap(\.bundleIdentifier))
        for bid in missingSince.keys where !runningIDs.contains(bid) || !app.isBlockActive {
            missingSince[bid] = nil
            closing.remove(bid)
            app.overlay.close(.browserWarning)
        }
        guard app.isBlockActive else { return }

        let state = app.state
        let blocked = Set(Engine.blockedApps(state, now: now))
        let known = Set(state.settings.knownBrowsers)
        let supported = Set(state.settings.supportedBrowsers.keys)

        for run in running {
            guard let bid = run.bundleIdentifier, !protected.contains(bid) else { continue }
            let name = run.localizedName ?? bid
            if blocked.contains(bid) {
                run.forceTerminate()
                notify(bid, now: now) { app.overlay.showBlocked(target: bid, kind: .app) }
            } else if supported.contains(bid) {
                checkHeartbeat(run, bid: bid, name: name, now: now)
            } else if known.contains(bid) {
                run.forceTerminate()
                let names = app.installedBrowsers.map(\.name)
                let use = names.isEmpty ? "a supported browser" : names.joined(separator: " or ")
                notify(bid, now: now) {
                    app.overlay.showBrowserWarning(appName: name, reason: "\(name) can't be used during a session — use \(use).",
                                                   deadline: nil)
                }
            }
        }
    }

    // Our bridge being down is not the user's fault. An idle background browser isn't a bypass either, so a missing
    // heartbeat only counts while the browser is the frontmost app and has been for heartbeatGrace.
    private func checkHeartbeat(_ run: NSRunningApplication, bid: String, name: String, now: Date) {
        let frontmost = frontApp.map { $0.bid == bid && now.timeIntervalSince($0.since) >= heartbeatGrace } ?? false
        let missing = app.bridgeListening && frontmost && !app.connectedBrowsers.contains(bid)
        guard missing else {
            if missingSince.removeValue(forKey: bid) != nil { app.overlay.close(.browserWarning) }
            closing.remove(bid)
            return
        }
        let since = missingSince[bid] ?? now
        if missingSince[bid] == nil {
            missingSince[bid] = now
            app.overlay.showBrowserWarning(
                appName: name,
                reason: "\(name) was disconnected from Focus. Reconnect the Focus extension, or the browser will close in 20 s.",
                deadline: now.addingTimeInterval(warningPeriod))
        }
        guard now.timeIntervalSince(since) >= warningPeriod, !closing.contains(bid) else { return }
        closing.insert(bid)
        run.terminate()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            if !run.isTerminated { run.forceTerminate() }
        }
    }

    private func notify(_ bid: String, now: Date, _ show: () -> Void) {
        if let shown = lastShown[bid], now.timeIntervalSince(shown) < 10 { return }
        lastShown[bid] = now
        show()
    }
}
