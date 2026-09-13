import Foundation

/// Capacity numbers for the boot volume, matching what Finder / About This Mac report.
struct VolumeInfo {
    var total: Int64 = 0
    var available: Int64 = 0          // free right now
    var availableImportant: Int64 = 0 // free after macOS purges purgeable content
    var name: String = "Macintosh HD"

    var used: Int64 { max(0, total - availableImportant) }
    var purgeable: Int64 { max(0, availableImportant - available) }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
    var purgeableFraction: Double { total > 0 ? Double(purgeable) / Double(total) : 0 }

    static func current() -> VolumeInfo {
        var v = VolumeInfo()
        let url = URL(fileURLWithPath: "/")
        if let r = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeLocalizedNameKey]) {
            v.total = Int64(r.volumeTotalCapacity ?? 0)
            v.available = Int64(r.volumeAvailableCapacity ?? 0)
            v.availableImportant = r.volumeAvailableCapacityForImportantUsage ?? v.available
            v.name = r.volumeLocalizedName ?? v.name
        }
        return v
    }
}

/// Full Disk Access is a TCC permission; there is no API to query it. Probing a protected folder is
/// the standard technique, `~/Library/Safari` is unreadable without it.
enum FullDiskAccess {
    static func check() -> Bool {
        let probe = NSHomeDirectory() + "/Library/Safari"
        let fd = open(probe, O_RDONLY | O_DIRECTORY)
        if fd >= 0 { close(fd); return true }
        return errno != EPERM && errno != EACCES ? false : false
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}

import AppKit
