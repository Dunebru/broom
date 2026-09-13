import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $model.section) { s in
                Label(s.rawValue, systemImage: s.symbol).tag(s)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
            .safeAreaInset(edge: .bottom) { sidebarFooter }
        } detail: {
            Group {
                switch model.section {
                case .overview: OverviewView()
                case .map: StorageMapView()
                case .clean: CleanView()
                case .large: LargeFilesView()
                case .apps: AppsView()
                case .snapshots: SnapshotsView()
                }
            }
            .navigationTitle(model.section.rawValue)
            .toolbar { toolbar }
        }
        .onAppear { if model.junk.isEmpty { model.analyzeJunk() } }
        .alert("Something went wrong", isPresented: Binding(get: { model.lastError != nil }, set: { if !$0 { model.lastError = nil } })) {
            Button("OK") { model.lastError = nil }
        } message: { Text(model.lastError ?? "") }
    }

    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            if !model.hasFullDiskAccess {
                Button {
                    FullDiskAccess.openSettings()
                } label: {
                    Label("Grant Full Disk Access", systemImage: "lock.open")
                        .font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain).foregroundStyle(Color.accentColor)
                .help("Without it, Mail, Safari and Time Machine data are invisible and totals are lower than Finder's.")
            }
            HStack(spacing: 6) {
                Image(systemName: "internaldrive").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.volume.name).font(.caption.weight(.medium))
                    Text("\(Format.bytes(model.volume.available)) free of \(Format.bytes(model.volume.total))").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(.top, 2)
        }
        .padding(10)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if model.isScanning {
                ProgressView().controlSize(.small)
                Text("\(Format.count(model.progress.files)) files · \(Format.bytes(model.progress.bytes))")
                    .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                Button("Stop", systemImage: "stop.circle") { model.cancelScan() }
            } else {
                Menu {
                    Button("Home Folder") { model.startScan(.home) }
                    Button("Whole Disk") { model.startScan(.disk) }
                    Divider()
                    Button("Choose Folder…") { chooseFolder() }
                } label: {
                    Label(model.root == nil ? "Scan" : "Rescan · \(model.target.title)", systemImage: "arrow.clockwise")
                } primaryAction: {
                    model.startScan(model.target)
                }
                .help("Scan a folder or the whole disk to build the storage map")
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.prompt = "Scan"
        if panel.runModal() == .OK, let url = panel.url { model.startScan(.folder(url)) }
    }
}

// MARK: - Shared components

struct StatCard<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var action: (() -> Void)? = nil
    var actionTitle: String = "Scan"
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 44, weight: .light)).foregroundStyle(.tertiary)
            Text(title).font(.title3.weight(.semibold))
            Text(message).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 380)
            if let action { Button(actionTitle, action: action).buttonStyle(.borderedProminent).controlSize(.large).padding(.top, 4) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SizeBar: View {
    let fraction: Double
    var color: Color = .accentColor
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(color).frame(width: max(2, g.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: 5)
    }
}

extension View {
    /// Applies a monospaced-digit callout style for sizes in lists.
    func sizeStyle() -> some View { font(.callout.monospacedDigit()).foregroundStyle(.secondary) }
}
