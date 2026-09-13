import AppKit
import Foundation

/// Items staged for removal. Nothing is touched until `commit()`.
struct Collector {
    private(set) var nodes: [FileNode] = []

    var total: Int64 { nodes.reduce(0) { $0 + $1.size } }
    var isEmpty: Bool { nodes.isEmpty }
    var count: Int { nodes.count }

    func contains(_ n: FileNode) -> Bool { nodes.contains { $0 === n } }

    mutating func toggle(_ n: FileNode) {
        if let i = nodes.firstIndex(where: { $0 === n }) { nodes.remove(at: i) } else { add(n) }
    }

    mutating func add(_ n: FileNode) {
        guard !contains(n) else { return }
        // Drop descendants of the new item and skip if an ancestor is already staged.
        if nodes.contains(where: { n.isDescendant(of: $0) }) { return }
        nodes.removeAll { $0.isDescendant(of: n) }
        nodes.append(n)
    }

    mutating func remove(_ n: FileNode) { nodes.removeAll { $0 === n } }
    mutating func clear() { nodes.removeAll() }
}

enum Trash {
    struct Result { var moved: Int = 0; var bytes: Int64 = 0; var failures: [(String, String)] = [] }

    /// Move each URL to the Trash (reversible). Runs synchronously; call off the main thread.
    static func move(_ urls: [(URL, Int64)]) -> Result {
        var r = Result()
        for (url, size) in urls {
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                r.moved += 1; r.bytes += size
            } catch {
                r.failures.append((url.path, error.localizedDescription))
            }
        }
        return r
    }

    /// Permanently remove (for caches that regenerate). Only used by cleaner categories flagged `.remove`.
    static func remove(_ urls: [(URL, Int64)]) -> Result {
        var r = Result()
        for (url, size) in urls {
            do {
                try FileManager.default.removeItem(at: url)
                r.moved += 1; r.bytes += size
            } catch {
                r.failures.append((url.path, error.localizedDescription))
            }
        }
        return r
    }

    static func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
}
