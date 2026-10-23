import AppKit
import Foundation
import FocusCore

struct InstalledBrowser: Identifiable {
    let bundleID: String
    let name: String
    var id: String { bundleID }
}

@MainActor
final class AppController: ObservableObject {
    @Published private(set) var state: AppState
    @Published private(set) var now = Date()
    @Published private(set) var connectedBrowsers: Set<String> = []
    @Published private(set) var browserSeen: [String: Date] = [:]
    @Published private(set) var bridgeListening = false
    @Published var lastError: String?

    private let store = Store()
    private(set) var overlay: OverlayController!
    private var blocker: AppBlocker!
    private var bridge: BridgeServer!
    private var timer: Timer?
    private var ticks = 0
    private var lastRules = BridgeRules.empty
    private var lastMarker: Date?

    init() {
        state = store.load()
        now = TrustedClock.now(anchor: &state.clock)
        overlay = OverlayController(app: self)
        blocker = AppBlocker(app: self)
        bridge = BridgeServer()
        bridge.rulesProvider = { [weak self] in self?.bridgeRules ?? .empty }
        bridge.allowedBrowsers = { [weak self] in self.map { Set($0.state.settings.supportedBrowsers.keys) } ?? [] }
        bridge.onError = { [weak self] in self?.lastError = $0 }
        bridge.onListening = { [weak self] listening in
            self?.bridgeListening = listening
            if listening { self?.lastError = nil }
        }
        bridge.start()
        lastMarker = blockUntil
        store.writeActiveBlockMarker(until: lastMarker)
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    var activeBlocks: [ActiveBlock] { Engine.activeBlocks(state, now: now) }
    var isBlockActive: Bool { Engine.isBlockActive(state, now: now) }

    var installedBrowsers: [InstalledBrowser] {
        state.settings.supportedBrowsers.keys.compactMap { bid in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) else { return nil }
            return InstalledBrowser(bundleID: bid, name: FileManager.default.displayName(atPath: url.path))
        }
        .sorted { $0.name < $1.name }
    }

    var canEmergencyExit: Bool {
        isBlockActive && state.settings.emergencyEnabled
    }

    var bridgeRules: BridgeRules {
        let blocks = activeBlocks
        guard !blocks.isEmpty else { return .empty }
        return BridgeRules(blockedDomains: Engine.blockedDomains(state, now: now),
                           until: blocks.map(\.end).max())
    }

    private var blockUntil: Date? {
        isBlockActive ? activeBlocks.map(\.end).max() : nil
    }

    func startSession(modeID: UUID, minutes: Int) {
        let session = Session(id: UUID(), modeID: modeID, start: now,
                              end: now.addingTimeInterval(TimeInterval(minutes * 60)))
        commit { $0.sessions.append(session) }
        store.append(.sessionStarted(modeID: modeID, minutes: minutes))
    }

    @discardableResult
    func update(_ mutate: (inout AppState) -> Void) -> Bool {
        var next = state
        mutate(&next)
        next.clock = state.clock
        guard Engine.validateEdit(old: state, new: next, now: now) else {
            lastError = "This can't be changed while a block is active."
            store.append(.editRejected(reason: lastError ?? ""))
            return false
        }
        lastError = nil
        state = next
        store.save(state)
        return true
    }

    func requestEmergency() {
        guard canEmergencyExit else { return }
        let length = state.settings.emergencyPhraseLength
        commit { $0.emergency = EmergencyRequest(requestedAt: now, phrase: Engine.emergencyPhrase(length: length)) }
    }

    func cancelEmergency() {
        guard state.emergency != nil else { return }
        commit { $0.emergency = nil }
    }

    func confirmEmergency(reason: String) -> Bool {
        guard canEmergencyExit, let request = state.emergency else { return false }
        let wait = TimeInterval(state.settings.emergencyWaitMinutes * 60)
        guard now >= request.requestedAt.addingTimeInterval(wait) else {
            lastError = "Wait for the countdown to finish."
            return false
        }
        commit { Engine.applyEmergency(&$0, now: now) }
        store.append(.emergencyUsed(reason: reason))
        return true
    }

    func showSettings() {
        overlay.showSettings()
    }

    func showEmergency() {
        overlay.showEmergency()
    }

    private func tick() {
        now = TrustedClock.now(anchor: &state.clock)
        let browsers = bridge.connectedBrowsers(now: Date())
        if browsers != connectedBrowsers { connectedBrowsers = browsers }
        if bridge.lastSeen != browserSeen { browserSeen = bridge.lastSeen }
        let rules = bridgeRules
        if rules != lastRules {
            lastRules = rules
            bridge.broadcast(rules)
        }
        let until = blockUntil
        if until != lastMarker {
            lastMarker = until
            store.writeActiveBlockMarker(until: until)
        }
        blocker.sweep()
        ticks += 1
        if ticks % 60 == 0 { store.save(state) }
    }

    private func commit(_ change: (inout AppState) -> Void) {
        change(&state)
        store.save(state)
    }
}
