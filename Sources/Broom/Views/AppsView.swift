import SwiftUI

struct AppsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var tab = 0
    @State private var selectedApp: InstalledApp?
    @State private var related: [JunkItem] = []
    @State private var loadingRelated = false
    @State private var confirmUninstall = false
    @State private var selectedLeftovers = Set<String>()
    @State private var confirmLeftovers = false
    @State private var search = ""

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("Leftovers (\(model.leftovers.count))").tag(0)
                Text("Installed Apps (\(model.installedApps.count))").tag(1)
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 320).padding(10)
            Divider()
            if tab == 0 { leftovers } else { installed }
        }
        .onAppear { selectedLeftovers = Set(model.leftovers.map(\.id)) }
        .onChange(of: model.leftovers.map(\.id)) { _, ids in selectedLeftovers = Set(ids) }
    }

    // MARK: leftovers

    private var leftovers: some View {
        Group {
            if model.isAnalyzingJunk && model.leftovers.isEmpty {
                VStack(spacing: 12) { ProgressView().controlSize(.large); Text("Checking for leftovers…").foregroundStyle(.secondary) }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.leftovers.isEmpty {
                EmptyStateView(symbol: "app.dashed", title: "No leftovers", message: "Every support folder, cache and preference file on this Mac belongs to an app that is still installed.")
            } else {
                VStack(spacing: 0) {
                    List {
                        ForEach(model.leftovers) { l in
                            DisclosureGroup {
                                ForEach(l.items) { i in
                                    HStack {
                                        Text(i.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")).font(.caption).lineLimit(1).truncationMode(.middle)
                                        Spacer()
                                        Text(Format.bytes(i.size)).sizeStyle()
                                        Button { Trash.reveal(i.url) } label: { Image(systemName: "magnifyingglass") }.buttonStyle(.plain).foregroundStyle(.secondary)
                                    }
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    Toggle("", isOn: Binding(get: { selectedLeftovers.contains(l.id) }, set: { on in if on { selectedLeftovers.insert(l.id) } else { selectedLeftovers.remove(l.id) } })).toggleStyle(.checkbox).labelsHidden()
                                    Image(systemName: "app.dashed").foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(l.displayName).font(.callout.weight(.semibold))
                                        Text("\(l.bundleID) · \(l.items.count) item\(l.items.count == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(Format.bytes(l.size)).font(.callout.weight(.medium).monospacedDigit())
                                }
                            }
                        }
                    }
                    .listStyle(.inset)
                    HStack {
                        Text("Only data whose app is gone and whose vendor has no other app installed is listed. Moved to the Trash.").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Remove Selected") { confirmLeftovers = true }.buttonStyle(.borderedProminent).disabled(selectedLeftovers.isEmpty)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10).background(.bar).overlay(alignment: .top) { Divider() }
                }
                .confirmationDialog("Move leftovers of \(selectedLeftovers.count) app\(selectedLeftovers.count == 1 ? "" : "s") to the Trash?", isPresented: $confirmLeftovers, titleVisibility: .visible) {
                    Button("Move to Trash", role: .destructive) {
                        let items = model.leftovers.filter { selectedLeftovers.contains($0.id) }.flatMap(\.items).map { ($0.url, $0.size) }
                        DispatchQueue.global().async {
                            let r = Trash.move(items)
                            DispatchQueue.main.async {
                                if !r.failures.isEmpty { model.lastError = r.failures.map { "\($0.0): \($0.1)" }.joined(separator: "\n") }
                                model.analyzeJunk()
                            }
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                }
            }
        }
    }

    // MARK: installed apps

    private var filteredApps: [InstalledApp] {
        let apps = model.installedApps.filter { !$0.isApple }
        return search.isEmpty ? apps : apps.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.bundleID.localizedCaseInsensitiveContains(search) }
    }

    private var installed: some View {
        HSplitView {
            VStack(spacing: 0) {
                TextField("Search apps", text: $search).textFieldStyle(.roundedBorder).padding(8)
                List(filteredApps, selection: $selectedApp) { a in
                    HStack(spacing: 8) {
                        Image(nsImage: a.icon).resizable().frame(width: 22, height: 22)
                        Text(a.name).lineLimit(1)
                        Spacer()
                        Text(Format.bytes(a.size)).sizeStyle()
                    }
                    .tag(a)
                }
                .onChange(of: selectedApp) { _, app in loadRelated(app) }
            }
            .frame(minWidth: 280, idealWidth: 320, maxWidth: 420)

            if let a = selectedApp {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(nsImage: a.icon).resizable().frame(width: 56, height: 56)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(a.name).font(.title2.weight(.bold))
                            Text(a.bundleID).font(.caption).foregroundStyle(.secondary)
                            Text(a.url.path).font(.caption).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Button { Trash.reveal(a.url) } label: { Label("Show in Finder", systemImage: "magnifyingglass") }
                    }
                    Divider()
                    Text("Related data").font(.callout.weight(.semibold))
                    if loadingRelated { ProgressView().controlSize(.small) }
                    else if related.isEmpty { Text("No support files, caches or preferences found outside the app bundle.").font(.callout).foregroundStyle(.secondary) }
                    else {
                        List {
                            ForEach(related) { i in
                                HStack {
                                    Text(i.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")).font(.caption).lineLimit(1).truncationMode(.middle)
                                    Spacer()
                                    Text(Format.bytes(i.size)).sizeStyle()
                                }
                            }
                        }
                        .listStyle(.bordered)
                    }
                    Spacer()
                    HStack {
                        Text("Uninstall moves the app and \(Format.bytes(related.reduce(0) { $0 + $1.size })) of related data to the Trash.").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Uninstall…", role: .destructive) { confirmUninstall = true }.buttonStyle(.borderedProminent).tint(.red)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .confirmationDialog("Uninstall \(a.name) and its related data?", isPresented: $confirmUninstall, titleVisibility: .visible) {
                    Button("Uninstall", role: .destructive) { uninstall(a) }
                    Button("Cancel", role: .cancel) {}
                } message: { Text("Everything goes to the Trash. Quit the app first if it is running.") }
            } else {
                EmptyStateView(symbol: "app.badge.checkmark", title: "Pick an app", message: "See what an app leaves in Library folders and uninstall it completely.")
            }
        }
    }

    private func loadRelated(_ app: InstalledApp?) {
        related = []
        guard let app else { return }
        loadingRelated = true
        DispatchQueue.global(qos: .userInitiated).async {
            let r = AppInventory.relatedFiles(for: app)
            DispatchQueue.main.async { if selectedApp == app { related = r; loadingRelated = false } }
        }
    }

    private func uninstall(_ app: InstalledApp) {
        let items = [(app.url, app.size)] + related.map { ($0.url, $0.size) }
        selectedApp = nil
        DispatchQueue.global().async {
            let r = Trash.move(items)
            DispatchQueue.main.async {
                if !r.failures.isEmpty { model.lastError = r.failures.map { "\($0.0): \($0.1)" }.joined(separator: "\n") }
                model.analyzeJunk()
            }
        }
    }
}
