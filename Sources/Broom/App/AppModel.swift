import Foundation
import SwiftUI

enum Pane: String, CaseIterable, Identifiable {
    case overview = "Overview", map = "Storage Map", clean = "Clean", large = "Large Files", apps = "Apps", snapshots = "Snapshots"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .overview: "gauge.with.dots.needle.33percent"
        case .map: "chart.pie"
        case .clean: "sparkles"
        case .large: "doc.zipper"
        case .apps: "app.badge.checkmark"
        case .snapshots: "clock.arrow.circlepath"
        }
    }
}

enum ScanTarget: Equatable {
    case home, disk, folder(URL)
    var path: String {
        switch self {
        case .home: NSHomeDirectory()
        case .disk: "/"
        case .folder(let u): u.path
        }
    }
    var title: String {
        switch self {
        case .home: "Home"
        case .disk: "Macintosh HD"
        case .folder(let u): u.lastPathComponent
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var section: Pane = .overview
    @Published var root: FileNode?
    @Published var target: ScanTarget = .home
    @Published var isScanning = false
    @Published var progress = BulkScanner.Progress()
    @Published var scanDuration: TimeInterval = 0
    @Published var volume = VolumeInfo.current()
    @Published var hasFullDiskAccess = FullDiskAccess.check()
    @Published var collector = Collector()
    @Published var lastError: String?

    // Cleaner
    @Published var junk: [JunkCategory] = []
    @Published var isAnalyzingJunk = false
    @Published var leftovers: [AppLeftover] = []
    @Published var installedApps: [InstalledApp] = []
    @Published var snapshots: [LocalSnapshot] = []

    private var scanner: BulkScanner?
    private var ticker: Timer?

    init() {
        // Launch arguments for scripting and screenshots: --pane <name> --scan home|disk|<path>
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--pane"), args.count > i + 1, let p = Pane.allCases.first(where: { $0.rawValue.lowercased().contains(args[i + 1].lowercased()) }) { section = p }
        if let i = args.firstIndex(of: "--scan"), args.count > i + 1 {
            let t: ScanTarget = args[i + 1] == "home" ? .home : args[i + 1] == "disk" ? .disk : .folder(URL(fileURLWithPath: args[i + 1]))
            DispatchQueue.main.async { [weak self] in self?.startScan(t) }
        }
    }

    func startScan(_ target: ScanTarget) {
        guard !isScanning else { return }
        self.target = target
        isScanning = true
        progress = .init()
        let scanner = BulkScanner()
        self.scanner = scanner
        let path = target.path
        let started = Date()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let s = self.scanner else { return }
            let p = s.progress
            DispatchQueue.main.async { self.progress = p }
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let root = scanner.scan(path: path)
            DispatchQueue.main.async {
                guard let self else { return }
                self.ticker?.invalidate(); self.ticker = nil
                self.progress = scanner.progress
                self.root = root
                self.scanDuration = Date().timeIntervalSince(started)
                self.isScanning = false
                self.volume = VolumeInfo.current()
            }
        }
    }

    func cancelScan() { scanner?.cancel() }

    func refreshAccess() { hasFullDiskAccess = FullDiskAccess.check(); volume = VolumeInfo.current() }

    // MARK: cleaner

    func analyzeJunk() {
        guard !isAnalyzingJunk else { return }
        isAnalyzingJunk = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let cats = JunkRules.analyze()
            let apps = AppInventory.installedApps()
            let left = AppInventory.leftovers(installed: apps)
            let snaps = LocalSnapshot.list()
            DispatchQueue.main.async {
                guard let self else { return }
                self.junk = cats
                self.installedApps = apps
                self.leftovers = left
                self.snapshots = snaps
                self.isAnalyzingJunk = false
            }
        }
    }

    var selectedJunkBytes: Int64 {
        junk.reduce(0) { $0 + $1.items.filter(\.selected).reduce(0) { $0 + $1.size } }
    }
}
