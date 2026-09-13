import Darwin
import Foundation

/// Fast directory tree scanner built on getattrlistbulk(2).
///
/// One syscall returns a whole batch of entries with the attributes we need (type, allocated size,
/// modification time, inode, link count), so a home folder with hundreds of thousands of files scans in
/// a few seconds. Work fans out across a small pool of threads because APFS serializes reads inside a
/// single directory but parallelises well across directories.
public final class BulkScanner: @unchecked Sendable {

    public struct Progress: Sendable {
        public var files: Int = 0
        public var directories: Int = 0
        public var bytes: Int64 = 0
        public var currentPath: String = ""
    }

    public struct Options: Sendable {
        /// Paths never descended into (compared as full paths).
        public var excludedPaths: Set<String> = [
            "/Volumes", "/System/Volumes", "/dev", "/Network", "/.vol", "/private/var/vm", "/cores",
        ]
        /// Directory names never descended into anywhere in the tree.
        public var excludedNames: Set<String> = [".Spotlight-V100", ".fseventsd", ".DocumentRevisions-V100", ".TemporaryItems"]
        public var workers: Int = 10
        public init() {}
    }

    private let options: Options
    private let queue: DispatchQueue
    private let semaphore: DispatchSemaphore
    private let group = DispatchGroup()
    private let stateLock = NSLock()
    private var _progress = Progress()
    private var _canceled = false
    private var seenHardlinks = Set<UInt64>()
    private var allowedDevices = Set<UInt32>()

    public init(options: Options = Options()) {
        self.options = options
        self.queue = DispatchQueue(label: "broom.scanner", qos: .userInitiated, attributes: .concurrent)
        self.semaphore = DispatchSemaphore(value: max(1, options.workers))
    }

    public var progress: Progress {
        stateLock.lock(); defer { stateLock.unlock() }
        return _progress
    }

    public func cancel() {
        stateLock.lock(); _canceled = true; stateLock.unlock()
    }

    private var isCanceled: Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return _canceled
    }

    /// Scan `path` synchronously (call from a background thread). Returns the root node.
    public func scan(path: String) -> FileNode {
        let root = FileNode(name: path, isDirectory: true)
        stateLock.lock()
        _canceled = false; _progress = Progress(); seenHardlinks.removeAll()
        // Boot volume + Data volume are the only filesystems we descend into.
        allowedDevices = Set([path, "/", "/System/Volumes/Data"].compactMap { p -> UInt32? in
            guard let n = (try? FileManager.default.attributesOfItem(atPath: p))?[.systemNumber] as? Int else { return nil }
            return UInt32(truncatingIfNeeded: n)
        })
        stateLock.unlock()
        scanDirectory(root, path: path, depth: 0)
        group.wait()
        finalize(root)
        return root
    }

    // MARK: - traversal

    private func scanDirectory(_ node: FileNode, path: String, depth: Int) {
        if isCanceled { return }
        let entries = readEntries(path: path, node: node)
        var children: [FileNode] = []
        children.reserveCapacity(entries.count)
        var subdirs: [(FileNode, String)] = []

        for e in entries {
            switch e.kind {
            case .directory:
                let childPath = path == "/" ? "/" + e.name : path + "/" + e.name
                if options.excludedNames.contains(e.name) || options.excludedPaths.contains(childPath) { continue }
                if e.device != 0, !allowedDevices.isEmpty, !allowedDevices.contains(e.device) { continue }   // other filesystem (mount point)
                let child = FileNode(name: e.name, isDirectory: true, modified: e.modified, parent: node)
                children.append(child)
                subdirs.append((child, childPath))
            case .file:
                if e.linkCount > 1 {
                    stateLock.lock()
                    let dup = !seenHardlinks.insert(e.fileID).inserted
                    stateLock.unlock()
                    if dup { continue }
                }
                children.append(FileNode(name: e.name, isDirectory: false, size: e.allocated, modified: e.modified, parent: node))
            case .other:
                continue
            }
        }
        node.attach(children: children)   // sizes filled in later by finalize(); this sets the child list

        stateLock.lock()
        _progress.directories += 1
        _progress.files += children.count - subdirs.count
        for c in children where !c.isDirectory { _progress.bytes += c.size }
        _progress.currentPath = path
        stateLock.unlock()

        for (child, childPath) in subdirs {
            if depth < 4 {
                // Fan out near the top of the tree; deeper levels are scanned inline by the worker that got there.
                group.enter()
                queue.async { [self] in
                    semaphore.wait()
                    scanDirectory(child, path: childPath, depth: depth + 1)
                    semaphore.signal()
                    group.leave()
                }
            } else {
                scanDirectory(child, path: childPath, depth: depth + 1)
            }
        }
    }

    /// Post-order size roll-up and sort, done once all workers are finished.
    private func finalize(_ node: FileNode) {
        for c in node.children where c.isDirectory { finalize(c) }
        node.attach(children: node.children)
    }

    // MARK: - getattrlistbulk

    // Attribute masks as attrgroup_t (the C macros import with mixed signedness).
    private static let cmnReturned   = attrgroup_t(bitPattern: Int32(bitPattern: UInt32(ATTR_CMN_RETURNED_ATTRS)))
    private static let cmnError      = attrgroup_t(bitPattern: ATTR_CMN_ERROR)
    private static let cmnName       = attrgroup_t(bitPattern: ATTR_CMN_NAME)
    private static let cmnDevID      = attrgroup_t(bitPattern: ATTR_CMN_DEVID)
    private static let cmnObjType    = attrgroup_t(bitPattern: ATTR_CMN_OBJTYPE)
    private static let cmnModTime    = attrgroup_t(bitPattern: ATTR_CMN_MODTIME)
    private static let cmnFileID     = attrgroup_t(bitPattern: ATTR_CMN_FILEID)
    private static let fileLinkCount = attrgroup_t(bitPattern: ATTR_FILE_LINKCOUNT)
    private static let fileAllocSize = attrgroup_t(bitPattern: ATTR_FILE_ALLOCSIZE)

    private enum Kind { case file, directory, other }

    private struct Entry {
        var name: String
        var kind: Kind
        var allocated: Int64
        var modified: Date?
        var fileID: UInt64
        var linkCount: UInt32
        var device: UInt32
    }

    private func readEntries(path: String, node: FileNode) -> [Entry] {
        let fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        if fd < 0 {
            node.markInaccessible()
            return []
        }
        defer { close(fd) }

        // A mount point reports its parent's device in the directory listing, so check the real
        // filesystem once the directory is open. Anything not on the boot/Data volume is skipped:
        // external disks, simulator runtime images, iPhone DeviceFS mounts, network shares.
        var st = stat()
        if fstat(fd, &st) == 0, !allowedDevices.isEmpty, !allowedDevices.contains(UInt32(truncatingIfNeeded: st.st_dev)) {
            node.markForeignMount()
            return []
        }

        var attrs = attrlist()
        attrs.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        attrs.commonattr = Self.cmnReturned | Self.cmnError | Self.cmnName | Self.cmnDevID | Self.cmnObjType | Self.cmnModTime | Self.cmnFileID
        attrs.fileattr = Self.fileLinkCount | Self.fileAllocSize

        let bufferSize = 128 * 1024
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 8)
        defer { buffer.deallocate() }

        var out: [Entry] = []
        while true {
            let count = getattrlistbulk(fd, &attrs, buffer, bufferSize, UInt64(FSOPT_NOFOLLOW))
            if count < 0 {
                if errno == EINTR { continue }
                node.markInaccessible()
                break
            }
            if count == 0 { break }
            var cursor = buffer
            for _ in 0..<Int(count) {
                let recordLength = Int(cursor.loadUnaligned(as: UInt32.self))
                let record = cursor
                var p = cursor.advanced(by: 4)

                let returned = p.loadUnaligned(as: attribute_set_t.self)
                p = p.advanced(by: MemoryLayout<attribute_set_t>.size)

                var entry = Entry(name: "", kind: .other, allocated: 0, modified: nil, fileID: 0, linkCount: 1, device: 0)
                var error: UInt32 = 0
                if returned.commonattr & Self.cmnError != 0 {
                    error = p.loadUnaligned(as: UInt32.self); p = p.advanced(by: 4)
                }
                if returned.commonattr & Self.cmnName != 0 {
                    let ref = p.loadUnaligned(as: attrreference_t.self)
                    let namePtr = p.advanced(by: Int(ref.attr_dataoffset)).assumingMemoryBound(to: CChar.self)
                    entry.name = String(cString: namePtr)
                    p = p.advanced(by: MemoryLayout<attrreference_t>.size)
                }
                if returned.commonattr & Self.cmnDevID != 0 {
                    entry.device = p.loadUnaligned(as: UInt32.self); p = p.advanced(by: 4)
                }
                if returned.commonattr & Self.cmnObjType != 0 {
                    let t = p.loadUnaligned(as: fsobj_type_t.self); p = p.advanced(by: 4)
                    switch Int32(t) {
                    case Int32(VREG.rawValue): entry.kind = .file
                    case Int32(VDIR.rawValue): entry.kind = .directory
                    default: entry.kind = .other   // symlinks, sockets, fifos, devices
                    }
                }
                if returned.commonattr & Self.cmnModTime != 0 {
                    let ts = p.loadUnaligned(as: timespec.self); p = p.advanced(by: MemoryLayout<timespec>.size)
                    entry.modified = Date(timeIntervalSince1970: TimeInterval(ts.tv_sec))
                }
                if returned.commonattr & Self.cmnFileID != 0 {
                    entry.fileID = p.loadUnaligned(as: UInt64.self); p = p.advanced(by: 8)
                }
                if returned.fileattr & Self.fileLinkCount != 0 {
                    entry.linkCount = p.loadUnaligned(as: UInt32.self); p = p.advanced(by: 4)
                }
                if returned.fileattr & Self.fileAllocSize != 0 {
                    entry.allocated = p.loadUnaligned(as: Int64.self); p = p.advanced(by: 8)
                }
                if error == 0, !entry.name.isEmpty, entry.name != ".", entry.name != ".." {
                    out.append(entry)
                }
                cursor = record.advanced(by: recordLength)
            }
        }
        return out
    }
}
