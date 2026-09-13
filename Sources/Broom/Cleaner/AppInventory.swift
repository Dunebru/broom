import AppKit
import Foundation

struct InstalledApp: Identifiable, Hashable {
    let id: String        // bundle path
    let name: String
    let bundleID: String
    let url: URL
    let size: Int64
    let isApple: Bool
    var icon: NSImage { NSWorkspace.shared.icon(forFile: url.path) }
}

struct AppLeftover: Identifiable, Hashable {
    let id: String        // bundle id
    let bundleID: String
    let items: [JunkItem]
    var size: Int64 { items.reduce(0) { $0 + $1.size } }
    var displayName: String {
        // "com.vendor.AppName" → "AppName"; skip generic trailing parts like "client" or "helper"
        // so "com.spotify.client" reads as "Spotify".
        let generic: Set<String> = ["client", "app", "desktop", "console", "helper", "mac", "macos", "agent", "electron", "launcher", "main"]
        var parts = bundleID.split(separator: ".").map(String.init)
        while parts.count > 2, let last = parts.last, generic.contains(last.lowercased()) { parts.removeLast() }
        let name = parts.count >= 3 ? parts.last! : (parts.last ?? bundleID)
        return name.prefix(1).uppercased() + name.dropFirst()
    }
}

enum AppInventory {
    private static let home = NSHomeDirectory()

    /// Folders where apps leave data behind, keyed by how entries are named there.
    private static let leftoverRoots: [(path: String, suffix: String)] = [
        ("~/Library/Application Support", ""),
        ("~/Library/Caches", ""),
        ("~/Library/Containers", ""),
        ("~/Library/HTTPStorages", ""),
        ("~/Library/WebKit", ""),
        ("~/Library/Logs", ""),
        ("~/Library/Saved Application State", ".savedState"),
        ("~/Library/Preferences", ".plist"),
        ("~/Library/LaunchAgents", ".plist"),
        ("~/Library/Cookies", ".binarycookies"),
    ]

    static func installedApps() -> [InstalledApp] {
        let roots = ["/Applications", home + "/Applications", "/System/Applications", "/System/Applications/Utilities", "/Applications/Utilities", "/Library/Application Support/Setapp/Applications"]
        var out: [InstalledApp] = []
        var seen = Set<String>()
        for root in roots {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: root) else { continue }
            for name in names {
                let path = root + "/" + name
                let candidates = name.hasSuffix(".app") ? [path] : ((try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []).filter { $0.hasSuffix(".app") }.map { path + "/" + $0 }
                for appPath in candidates {
                    guard let bundle = Bundle(path: appPath), let bid = bundle.bundleIdentifier, !seen.contains(bid) else { continue }
                    seen.insert(bid)
                    let display = (bundle.infoDictionary?["CFBundleDisplayName"] as? String) ?? (bundle.infoDictionary?["CFBundleName"] as? String) ?? URL(fileURLWithPath: appPath).deletingPathExtension().lastPathComponent
                    let size = appPath.hasPrefix("/System") ? 0 : DirectorySize.of(appPath)
                    out.append(InstalledApp(id: appPath, name: display, bundleID: bid, url: URL(fileURLWithPath: appPath), size: size, isApple: bid.hasPrefix("com.apple.")))
                }
            }
        }
        return out.sorted { $0.size > $1.size }
    }

    /// Data left behind by apps that are no longer installed.
    static func leftovers(installed: [InstalledApp]) -> [AppLeftover] {
        var ids = Set(installed.map(\.bundleID))
        // Helpers and agents that are running right now clearly belong to something in use.
        for app in NSWorkspace.shared.runningApplications { if let b = app.bundleIdentifier { ids.insert(b) } }
        // Vendor prefixes ("com.google") of installed apps, anything sharing one is probably still in use
        // (helpers, updaters, shared frameworks), so it is never reported as a leftover.
        let vendors = Set(installed.compactMap { vendorPrefix($0.bundleID) })
        let runningVendors = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier.flatMap(vendorPrefix) })
        var byID: [String: [JunkItem]] = [:]
        for root in leftoverRoots {
            let dir = root.path.replacingOccurrences(of: "~", with: home)
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
            for name in names {
                var bid = name
                if !root.suffix.isEmpty {
                    guard name.hasSuffix(root.suffix) else { continue }
                    bid = String(name.dropLast(root.suffix.count))
                }
                guard looksLikeBundleID(bid), !bid.hasPrefix("com.apple."), !ids.contains(bid),
                      let vendor = vendorPrefix(bid), !vendors.contains(vendor) else { continue }
                // Launch Services knows every app bundle registered anywhere on disk (Homebrew casks,
                // ~/Applications subfolders, other volumes). If it can resolve the id, the app exists.
                if NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) != nil { continue }
                if runningVendors.contains(vendor) { continue }
                let full = dir + "/" + name
                let size = DirectorySize.of(full)
                guard size > 0 else { continue }
                let m = (try? FileManager.default.attributesOfItem(atPath: full))?[.modificationDate] as? Date
                byID[bid, default: []].append(JunkItem(id: full, url: URL(fileURLWithPath: full), size: size, modified: m, selected: true))
            }
        }
        return byID.map { AppLeftover(id: $0.key, bundleID: $0.key, items: $0.value.sorted { $0.size > $1.size }) }
            .sorted { $0.size > $1.size }
    }

    /// Everything on disk that belongs to an installed app (for a full uninstall).
    static func relatedFiles(for app: InstalledApp) -> [JunkItem] {
        var out: [JunkItem] = []
        for root in leftoverRoots {
            let dir = root.path.replacingOccurrences(of: "~", with: home)
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
            for name in names {
                var base = name
                if !root.suffix.isEmpty { guard name.hasSuffix(root.suffix) else { continue }; base = String(name.dropLast(root.suffix.count)) }
                guard base == app.bundleID || base.hasPrefix(app.bundleID + ".") || (root.suffix.isEmpty && base == app.name) else { continue }
                let full = dir + "/" + name
                let size = DirectorySize.of(full)
                let m = (try? FileManager.default.attributesOfItem(atPath: full))?[.modificationDate] as? Date
                out.append(JunkItem(id: full, url: URL(fileURLWithPath: full), size: size, modified: m, selected: true))
            }
        }
        return out.sorted { $0.size > $1.size }
    }

    private static func looksLikeBundleID(_ s: String) -> Bool {
        let parts = s.split(separator: ".")
        guard parts.count >= 3, !s.contains(" "), !s.contains("/") else { return false }
        return parts.allSatisfy { !$0.isEmpty }
    }

    private static func vendorPrefix(_ bid: String) -> String? {
        let parts = bid.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        return parts[0] + "." + parts[1]
    }
}
