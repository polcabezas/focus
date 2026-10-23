import AppKit
import Foundation
import Network
import OSLog
import FocusCore

private let log = Logger(subsystem: "com.pol.focus", category: "bridge")

struct BridgeRules: Equatable {
    var blockedDomains: [String]
    var until: Date?

    static let empty = BridgeRules(blockedDomains: [], until: nil)
}

// Origin is set by the browser, but a local process can fake it, so it is only a cheap first filter.
// The real identity check is clientOwner(port:).
private func isExtensionOrigin(_ origin: String) -> Bool {
    origin.hasPrefix("chrome-extension://") || origin.hasPrefix("safari-web-extension://") || origin.hasPrefix("webkit-extension://")
}

// Finds the process that owns the client end of a loopback connection (the server end is always our port), then the
// app responsible for it: a browser's helper process (WebKit.Networking, Arc Helper) resolves to the browser.
// Blocks on lsof, so call it off the main thread.
private func clientOwner(port: UInt16) -> (pid: pid_t, bundleID: String?) {
    let lsof = Process()
    lsof.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
    lsof.arguments = ["-nP", "-t", "-iTCP@127.0.0.1:\(port)", "-sTCP:ESTABLISHED"]
    let output = Pipe()
    lsof.standardOutput = output
    lsof.standardError = FileHandle.nullDevice
    guard (try? lsof.run()) != nil else { return (0, nil) }
    let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    lsof.waitUntilExit()
    let me = getpid()
    guard let pid = text.split(separator: "\n").compactMap({ pid_t($0) }).first(where: { $0 != me }) else { return (0, nil) }
    typealias ResponsibleFn = @convention(c) (pid_t) -> pid_t
    guard let symbol = dlsym(dlopen(nil, RTLD_NOW), "responsibility_get_pid_responsible_for_pid") else { return (pid, nil) }
    let responsible = unsafeBitCast(symbol, to: ResponsibleFn.self)(pid)
    return (pid, NSRunningApplication(processIdentifier: responsible)?.bundleIdentifier)
}

@MainActor
final class BridgeServer {
    var rulesProvider: () -> BridgeRules = { .empty }
    var allowedBrowsers: () -> Set<String> = { [] }
    var onError: ((String) -> Void)?
    var onListening: ((Bool) -> Void)?
    private(set) var isListening = false
    // Last time a verified browser was heard from (verification or any message), per bundle id. Survives disconnects.
    private(set) var lastSeen: [String: Date] = [:]

    private final class Peer {
        let connection: NWConnection
        var bundleID: String?          // set once the owning browser is verified; nil until then

        init(_ connection: NWConnection) { self.connection = connection }
    }

    private let port = NWEndpoint.Port(rawValue: 47823)!
    private var listener: NWListener?
    private var peers: [ObjectIdentifier: Peer] = [:]
    private let iso = ISO8601DateFormatter()

    func start() {
        guard listener == nil else { return }
        let websocket = NWProtocolWebSocket.Options()
        websocket.autoReplyPing = true
        websocket.setClientRequestHandler(.main) { _, headers in
            let origin = headers.first { $0.name.caseInsensitiveCompare("Origin") == .orderedSame }?.value.lowercased() ?? ""
            let accepted = isExtensionOrigin(origin)
            log.info("handshake origin \(origin, privacy: .public) \(accepted ? "accepted" : "rejected", privacy: .public)")
            return NWProtocolWebSocket.Response(status: accepted ? .accept : .reject, subprotocol: nil)
        }
        let params = NWParameters.tcp
        params.defaultProtocolStack.applicationProtocols.insert(websocket, at: 0)
        params.requiredInterfaceType = .loopback
        do {
            let listener = try NWListener(using: params, on: port)
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.accept(connection) }
            }
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in self?.listenerStateChanged(state) }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            fail("Browser bridge couldn't start: \(error.localizedDescription)")
        }
    }

    private func listenerStateChanged(_ state: NWListener.State) {
        log.info("listener \(String(describing: state), privacy: .public)")
        switch state {
        case .ready:
            setListening(true)
        case .failed(let error):
            listener?.cancel()
            listener = nil
            fail("Browser bridge stopped: \(error.localizedDescription)")
        case .cancelled:
            if listener != nil { fail("Browser bridge stopped.") }
        default:
            break
        }
    }

    private func fail(_ message: String) {
        log.error("\(message, privacy: .public)")
        setListening(false)
        onError?(message)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            self.start()
        }
    }

    private func setListening(_ value: Bool) {
        guard isListening != value else { return }
        isListening = value
        onListening?(value)
    }

    func connectedBrowsers(now: Date) -> Set<String> {
        Set(lastSeen.filter { now.timeIntervalSince($0.value) < 45 }.keys)
    }

    func broadcast(_ rules: BridgeRules) {
        for peer in peers.values { send(rules, to: peer.connection) }
    }

    private func accept(_ connection: NWConnection) {
        let key = ObjectIdentifier(connection)
        peers[key] = Peer(connection)
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in self?.connectionStateChanged(key, state) }
        }
        connection.start(queue: .main)
        receive(key: key)
    }

    private func connectionStateChanged(_ key: ObjectIdentifier, _ state: NWConnection.State) {
        switch state {
        case .ready:
            guard let peer = peers[key] else { return }
            guard case .hostPort(_, let clientPort) = peer.connection.endpoint else {
                drop(key, "no client port")
                return
            }
            Task { @MainActor [weak self] in
                let owner = await Task.detached { clientOwner(port: clientPort.rawValue) }.value
                self?.verify(key, owner)
            }
        case .waiting(let error):
            drop(key, "waiting: \(error.localizedDescription)")
        case .failed(let error):
            drop(key, "failed: \(error.localizedDescription)")
        case .cancelled:
            drop(key, "cancelled")
        default:
            break
        }
    }

    private func verify(_ key: ObjectIdentifier, _ owner: (pid: pid_t, bundleID: String?)) {
        guard let peer = peers[key] else { return }
        guard let bundleID = owner.bundleID, allowedBrowsers().contains(bundleID) else {
            drop(key, "client pid \(owner.pid) belongs to \(owner.bundleID ?? "unknown app"), not a supported browser")
            return
        }
        peer.bundleID = bundleID
        lastSeen[bundleID] = Date()
        log.info("connection ready, client pid \(owner.pid) browser \(bundleID, privacy: .public)")
        send(rulesProvider(), to: peer.connection)
    }

    private func drop(_ key: ObjectIdentifier, _ reason: String) {
        guard let peer = peers.removeValue(forKey: key) else { return }
        let left = peers.count
        log.info("peer removed (\(reason, privacy: .public)), \(left) left")
        peer.connection.cancel()
    }

    private func receive(key: ObjectIdentifier) {
        guard let connection = peers[key]?.connection else { return }
        connection.receiveMessage { [weak self] data, context, isComplete, error in
            let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata
            let isText = metadata?.opcode == .text
            let text = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
            let ended = context?.isFinal == true || ((data?.isEmpty ?? true) && isComplete)
            let closed = error.map { "receive error: \($0.localizedDescription)" } ?? (ended ? "peer closed" : nil)
            Task { @MainActor in
                guard let self else { return }
                if let closed {
                    self.drop(key, closed)
                    return
                }
                if isText { self.handle(text, key: key) }
                self.receive(key: key)
            }
        }
    }

    // Messages from a connection whose browser hasn't been verified yet are ignored.
    private func handle(_ text: String, key: ObjectIdentifier) {
        guard let peer = peers[key], let bundleID = peer.bundleID,
              let object = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any],
              let type = object["type"] as? String else { return }
        lastSeen[bundleID] = Date()
        switch type {
        case "hello":
            let ua = object["ua"] as? String ?? "-"
            log.info("hello ua \(ua, privacy: .public)")
            send(rulesProvider(), to: peer.connection)
        case "heartbeat":
            send(rulesProvider(), to: peer.connection)
        default:
            break
        }
    }

    private func send(_ rules: BridgeRules, to connection: NWConnection) {
        send([
            "type": "rules",
            "blockedDomains": rules.blockedDomains,
            "until": rules.until.map { iso.string(from: $0) as Any } ?? NSNull(),
        ], to: connection)
    }

    private func send(_ message: [String: Any], to connection: NWConnection) {
        guard let data = try? JSONSerialization.data(withJSONObject: message) else { return }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "rules", metadata: [metadata])
        connection.send(content: data, contentContext: context, isComplete: true, completion: .idempotent)
    }
}
