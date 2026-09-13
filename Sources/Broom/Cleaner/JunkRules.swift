import Foundation

enum DeletionMode { case trash, remove }
enum Risk { case safe, caution }

struct JunkItem: Identifiable, Hashable {
    let id: String            // path
    let url: URL
    let size: Int64
    let modified: Date?
    var selected: Bool
    var note: String? = nil
    var name: String { url.lastPathComponent }
}

struct JunkCategory: Identifiable {
    let id: String
    let name: String
    let symbol: String
    let explanation: String
    let risk: Risk
    let mode: DeletionMode
    var items: [JunkItem]
    var size: Int64 { items.reduce(0) { $0 + $1.size } }
    var selectedSize: Int64 { items.filter(\.selected).reduce(0) { $0 + $1.size } }
    var allSelected: Bool { !items.isEmpty && items.allSatisfy(\.selected) }
}

/// Declarative description of one junk source.
private struct Rule {
    enum Scope { case contents, whole }
    let id: String
    let name: String
    let symbol: String
    let explanation: String
    let risk: Risk
    let mode: DeletionMode
    let defaultOn: Bool
    let paths: [String]                   // "~" expanded
    let scope: Scope
    var extensions: Set<String>? = nil    // contents scope: keep only these file types
    var excludeNames: Set<String> = []
    var minAgeDays: Int = 0
    var keepNewest: Bool = false          // contents scope: newest item defaults off
}

enum JunkRules {
    private static let home = NSHomeDirectory()
    private static func p(_ s: String) -> String { s.hasPrefix("~") ? home + s.dropFirst() : s }

    private static let rules: [Rule] = [
        Rule(id: "caches", name: "App Caches", symbol: "internaldrive",
             explanation: "Temporary files apps keep to load faster. They are rebuilt automatically; apps may open a little slower the first time afterwards.",
             risk: .safe, mode: .remove, defaultOn: true,
             paths: ["~/Library/Caches"], scope: .contents,
             excludeNames: ["com.spotify.client", "CloudKit", "com.apple.bird", "com.apple.iCloudHelper", "com.apple.Safari", "Homebrew", "pip", "Yarn", "CocoaPods"]),
        Rule(id: "logs", name: "App Logs", symbol: "doc.text",
             explanation: "Activity logs written by apps. Crash reports in DiagnosticReports are kept because Apple Support uses them to diagnose problems.",
             risk: .safe, mode: .remove, defaultOn: true,
             paths: ["~/Library/Logs"], scope: .contents, excludeNames: ["DiagnosticReports", "CrashReporter"]),
        Rule(id: "xcode-derived", name: "Xcode Build Data", symbol: "hammer",
             explanation: "DerivedData holds intermediate builds and indexes. Xcode regenerates it on the next build; the first build takes longer.",
             risk: .safe, mode: .remove, defaultOn: true,
             paths: ["~/Library/Developer/Xcode/DerivedData"], scope: .contents),
        Rule(id: "xcode-support", name: "Xcode Device Support & Archives", symbol: "iphone.gen3",
             explanation: "Symbol files for old iOS versions and archived builds. Device support is re-downloaded when you connect that iOS version again. Archives contain the dSYMs for apps you shipped, keep them if you need to symbolicate crash reports.",
             risk: .caution, mode: .trash, defaultOn: false,
             paths: ["~/Library/Developer/Xcode/iOS DeviceSupport", "~/Library/Developer/Xcode/watchOS DeviceSupport", "~/Library/Developer/Xcode/tvOS DeviceSupport", "~/Library/Developer/Xcode/Archives"], scope: .contents),
        Rule(id: "simulator", name: "Simulator Caches", symbol: "ipad.and.iphone",
             explanation: "Caches from the iOS Simulator runtime. Your simulator devices and their apps are untouched.",
             risk: .safe, mode: .remove, defaultOn: true,
             paths: ["~/Library/Developer/CoreSimulator/Caches"], scope: .contents),
        Rule(id: "packages", name: "Package Manager Caches", symbol: "shippingbox",
             explanation: "Downloaded packages kept by Homebrew, npm, pip, uv, Yarn, pnpm, Cargo and CocoaPods. They are fetched again on demand.",
             risk: .safe, mode: .remove, defaultOn: true,
             paths: ["~/Library/Caches/Homebrew", "~/.npm/_cacache", "~/.cache", "~/Library/Caches/pip", "~/Library/Caches/Yarn", "~/Library/pnpm/store", "~/.cargo/registry/cache", "~/Library/Caches/CocoaPods", "~/Library/Caches/go-build"], scope: .whole),
        Rule(id: "gradle", name: "Gradle Caches", symbol: "cube.transparent",
             explanation: "Gradle keeps every dependency version ever used. Deleting means the next Android/JVM build re-downloads them, can be many gigabytes and slow.",
             risk: .caution, mode: .remove, defaultOn: false,
             paths: ["~/.gradle/caches"], scope: .whole),
        Rule(id: "mail", name: "Mail Attachments Cache", symbol: "envelope",
             explanation: "Copies of attachments Mail has opened or quick-looked. The originals stay in your mailbox.",
             risk: .safe, mode: .remove, defaultOn: true,
             paths: ["~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads"], scope: .contents),
        Rule(id: "installers", name: "Installers in Downloads", symbol: "arrow.down.circle",
             explanation: "Disk images and installer packages sitting in Downloads. Once an app is installed these are dead weight. Moved to the Trash, so you can get them back.",
             risk: .safe, mode: .trash, defaultOn: true,
             paths: ["~/Downloads"], scope: .contents, extensions: ["dmg", "pkg", "xip", "iso", "mpkg"]),
        Rule(id: "ios-backups", name: "iPhone & iPad Backups", symbol: "externaldrive.badge.icloud",
             explanation: "Local device backups made by Finder. The most recent backup is left unselected. Older ones are moved to the Trash.",
             risk: .caution, mode: .trash, defaultOn: true,
             paths: ["~/Library/Application Support/MobileSync/Backup"], scope: .contents, keepNewest: true),
        Rule(id: "trash", name: "Trash", symbol: "trash",
             explanation: "Everything currently in your Trash. Emptying it is permanent.",
             risk: .caution, mode: .remove, defaultOn: true,
             paths: ["~/.Trash"], scope: .contents),
    ]

    /// Measure every rule. Slow-ish (sizes whole folders); call off the main thread.
    static func analyze() -> [JunkCategory] {
        rules.compactMap { rule in
            var items: [JunkItem] = []
            for raw in rule.paths {
                let path = p(raw)
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { continue }
                switch rule.scope {
                case .whole:
                    let size = DirectorySize.of(path)
                    if size > 0 {
                        items.append(JunkItem(id: path, url: URL(fileURLWithPath: path), size: size, modified: modDate(path), selected: rule.defaultOn))
                    }
                case .contents:
                    guard isDir.boolValue,
                          let names = try? FileManager.default.contentsOfDirectory(atPath: path) else { continue }
                    for name in names where !name.hasPrefix(".") || rule.id == "trash" {
                        if name == ".DS_Store" || rule.excludeNames.contains(name) { continue }
                        if let exts = rule.extensions, !exts.contains((name as NSString).pathExtension.lowercased()) { continue }
                        let full = path + "/" + name
                        let m = modDate(full)
                        if rule.minAgeDays > 0, let m, m > Date().addingTimeInterval(-Double(rule.minAgeDays) * 86400) { continue }
                        let size = DirectorySize.of(full)
                        if size <= 0 { continue }
                        items.append(JunkItem(id: full, url: URL(fileURLWithPath: full), size: size, modified: m, selected: rule.defaultOn))
                    }
                }
            }
            if rule.keepNewest, let newest = items.max(by: { ($0.modified ?? .distantPast) < ($1.modified ?? .distantPast) }),
               let i = items.firstIndex(where: { $0.id == newest.id }) {
                items[i].selected = false
                items[i].note = "Most recent backup, kept"
            }
            items.sort { $0.size > $1.size }
            guard !items.isEmpty else { return nil }
            return JunkCategory(id: rule.id, name: rule.name, symbol: rule.symbol, explanation: rule.explanation,
                                risk: rule.risk, mode: rule.mode, items: items)
        }
    }

    private static func modDate(_ path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }
}

enum DirectorySize {
    /// Allocated size of a file or directory tree, using the bulk scanner for speed.
    static func of(_ path: String) -> Int64 {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            let v = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
            return Int64(v?.totalFileAllocatedSize ?? v?.fileAllocatedSize ?? 0)
        }
        var opts = BulkScanner.Options()
        opts.workers = 3
        return BulkScanner(options: opts).scan(path: path).size
    }
}
