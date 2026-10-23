import Foundation

public final class Store {
    public static let directory: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Focus", isDirectory: true)

    private struct HistoryLine: Codable {
        let at: Date
        let event: HistoryEvent
    }

    public init() {}

    public func load() -> AppState {
        let url = file("state.json")
        guard let data = try? Data(contentsOf: url) else { return .seeded() }
        if let state = try? JSONDecoder().decode(AppState.self, from: data) { return state }
        // Keep the unreadable file instead of silently overwriting it with seeded data.
        let stamp = Int(Date().timeIntervalSince1970)
        try? FileManager.default.moveItem(at: url, to: file("state.json.corrupt-\(stamp)"))
        return .seeded()
    }

    public func save(_ state: AppState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        write(data, to: "state.json")
    }

    public func append(_ event: HistoryEvent) {
        guard var data = try? JSONEncoder().encode(HistoryLine(at: Date(), event: event)) else { return }
        data.append(0x0A)
        ensureDirectory()
        let url = file("history.jsonl")
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }

    public func writeActiveBlockMarker(until: Date?) {
        guard let until else {
            try? FileManager.default.removeItem(at: file("active-block-until"))
            return
        }
        write(Data(ISO8601DateFormatter().string(from: until).utf8), to: "active-block-until")
    }

    private func file(_ name: String) -> URL {
        Self.directory.appendingPathComponent(name)
    }

    private func ensureDirectory() {
        try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
    }

    private func write(_ data: Data, to name: String) {
        ensureDirectory()
        try? data.write(to: file(name), options: .atomic)
    }
}
