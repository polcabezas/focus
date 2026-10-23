import AppKit
import FocusCore

/// The browser extension that ships inside Focus.app, copied out of the bundle so the user can load it.
enum BundledExtension {
    static var destination: URL {
        Store.directory.appendingPathComponent("Extension", isDirectory: true)
    }

    /// Copies the bundled extension to the data folder when that copy is missing or another version. Returns its URL.
    static func install() throws -> URL {
        let fm = FileManager.default
        let source = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/extension", isDirectory: true)
        if !fm.fileExists(atPath: destination.path) || version(of: destination) != version(of: source) {
            try? fm.removeItem(at: destination)
            try fm.createDirectory(at: Store.directory, withIntermediateDirectories: true)
            try fm.copyItem(at: source, to: destination)
        }
        return destination
    }

    static func reveal() throws {
        NSWorkspace.shared.activateFileViewerSelecting([try install()])
    }

    private static func version(of folder: URL) -> String? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("manifest.json")),
              let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return manifest["version"] as? String
    }
}
