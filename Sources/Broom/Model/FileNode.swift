import Foundation

/// One entry in the scanned tree. Reference type so the tree can be built in place by parallel workers
/// and shared with the UI without copying. Immutable after the scan finishes.
public final class FileNode: Identifiable, Hashable, @unchecked Sendable {
    public let id: Int
    public let name: String
    public let isDirectory: Bool
    public private(set) var size: Int64          // allocated bytes, subtree total for directories
    public private(set) var fileCount: Int       // files in subtree (1 for a file)
    public let modified: Date?
    public private(set) var children: [FileNode] // sorted by size desc once finalized
    public private(set) weak var parent: FileNode?
    public private(set) var inaccessible: Bool   // permission denied while reading this directory
    public private(set) var foreignMount: Bool = false // another filesystem mounted here; not scanned

    init(name: String, isDirectory: Bool, size: Int64 = 0, modified: Date? = nil, parent: FileNode? = nil) {
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
        self.fileCount = isDirectory ? 0 : 1
        self.modified = modified
        self.children = []
        self.parent = parent
        self.inaccessible = false
        self.id = FileNode.nextID()
    }

    // MARK: building (scanner only)

    func attach(children: [FileNode]) {
        self.children = children.sorted { $0.size > $1.size }
        var total: Int64 = 0
        var count = 0
        for c in children { total += c.size; count += c.fileCount }
        size = total
        fileCount = count
    }

    func markInaccessible() { inaccessible = true }
    func markForeignMount() { foreignMount = true }

    // MARK: derived

    public var path: String {
        var parts: [String] = []
        var node: FileNode? = self
        while let n = node { parts.append(n.name); node = n.parent }
        let joined = parts.reversed().joined(separator: "/")
        return joined.hasPrefix("//") ? String(joined.dropFirst()) : joined
    }

    public var url: URL { URL(fileURLWithPath: path) }

    public var depth: Int {
        var d = 0; var n = parent
        while let p = n { d += 1; n = p.parent }
        return d
    }

    public var ancestors: [FileNode] {
        var out: [FileNode] = []; var n = parent
        while let p = n { out.append(p); n = p.parent }
        return out.reversed()
    }

    public func isDescendant(of other: FileNode) -> Bool {
        var n = parent
        while let p = n { if p === other { return true }; n = p.parent }
        return false
    }

    /// Depth-first walk, largest first. `body` returns false to skip a subtree.
    public func walk(_ body: (FileNode) -> Bool) {
        guard body(self) else { return }
        for c in children { c.walk(body) }
    }

    public static func == (lhs: FileNode, rhs: FileNode) -> Bool { lhs === rhs }
    public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}

private let idLock = NSLock()
private var idCounter = 0
extension FileNode {
    fileprivate static func nextID() -> Int { idLock.lock(); defer { idLock.unlock() }; idCounter += 1; return idCounter }
}
