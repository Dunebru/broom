import SwiftUI
import UniformTypeIdentifiers

struct StorageMapView: View {
    @EnvironmentObject private var model: AppModel
    @State private var zoom: FileNode? = nil
    @State private var hovered: Arc? = nil
    @State private var arcs: [Arc] = []
    @State private var showSmall = false
    @State private var confirmTrash = false
    @State private var trashing = false
    @State private var dropTargeted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    private var current: FileNode? { zoom ?? model.root }
    private var isWholeDisk: Bool { model.target == .disk }
    /// Space the volume reports as used that the scan could not account for (unreadable system data, other users, snapshots).
    private var hiddenBytes: Int64 { isWholeDisk ? max(0, model.volume.used - (model.root?.size ?? 0)) : 0 }

    var body: some View {
        if let root = model.root, let cur = current {
            VStack(spacing: 0) {
                breadcrumbs(for: cur, root: root)
                Divider()
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        SunburstView(root: cur, arcs: arcs, centerTitle: centerTitle(cur), hovered: $hovered,
                                     onSelect: { zoomTo($0) },
                                     onUp: { if let p = cur.parent { zoomTo(p) } })
                            .padding(20)
                            .id(cur.id)
                            .transition(reduceMotion ? .opacity : .scale(scale: 0.9).combined(with: .opacity))
                        collectorZone
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Divider()
                    legend(for: cur)
                        .frame(width: 320)
                }
            }
            .onAppear { relayout() }
            .onChange(of: model.root?.id) { _, _ in zoom = nil; relayout() }
            .onChange(of: zoom?.id) { _, _ in relayout() }
            .sheet(isPresented: $showSmall) { smallObjectsSheet(for: cur) }
            .confirmationDialog("Move \(model.collector.count) item\(model.collector.count == 1 ? "" : "s") (\(Format.bytes(model.collector.total))) to the Trash?", isPresented: $confirmTrash, titleVisibility: .visible) {
                Button("Move to Trash", role: .destructive) { commitCollector() }
                Button("Cancel", role: .cancel) {}
            } message: { Text("You can restore them from the Trash. Space is reclaimed when the Trash is emptied.") }
        } else if model.isScanning {
            VStack(spacing: 14) {
                ProgressView().controlSize(.large)
                Text("Scanning \(model.target.title)").font(.title3.weight(.semibold))
                Text("\(Format.count(model.progress.files)) files · \(Format.bytes(model.progress.bytes))").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                Text(model.progress.currentPath).font(.caption).foregroundStyle(.tertiary).lineLimit(1).frame(maxWidth: 480)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            EmptyStateView(symbol: "chart.pie", title: "No scan yet", message: "Scan the whole disk or your home folder to see every folder drawn to scale. Hover for sizes, click to dive in.", action: { model.startScan(.disk) }, actionTitle: "Scan Macintosh HD")
        }
    }

    // MARK: layout

    private func relayout() {
        guard let cur = current else { arcs = []; return }
        if isWholeDisk, cur.parent == nil, model.volume.total > 0 {
            arcs = SunburstLayout.arcs(for: cur, usedFraction: Double(cur.size) / Double(model.volume.total), hiddenBytes: hiddenBytes, capacity: model.volume.total)
        } else {
            arcs = SunburstLayout.arcs(for: cur)
        }
    }

    private func centerTitle(_ cur: FileNode) -> String {
        isWholeDisk && cur.parent == nil ? Format.bytes(model.volume.total) : Format.bytes(cur.size)
    }

    private func zoomTo(_ n: FileNode) {
        guard n.isDirectory else { return }
        hovered = nil
        withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 1)) { zoom = n === model.root ? nil : n }
    }

    // MARK: chrome

    private func breadcrumbs(for cur: FileNode, root: FileNode) -> some View {
        HStack(spacing: 6) {
            Button { if let p = cur.parent { zoomTo(p) } } label: { Image(systemName: "chevron.left") }.disabled(cur.parent == nil).help("Up one level")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(Array((cur.ancestors + [cur]).enumerated()), id: \.element.id) { i, n in
                        Button { zoomTo(n) } label: {
                            Text(n === root ? model.target.title : n.name)
                                .font(.callout.weight(n === cur ? .semibold : .regular))
                                .padding(.horizontal, 9).padding(.vertical, 4)
                                .background(n === cur ? Color.accentColor.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        if n !== cur { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
                    }
                }
            }
            Spacer()
            if let h = hovered?.node {
                Text(h.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).frame(maxWidth: 420, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    // MARK: legend (DaisyDisk-style)

    private func legend(for cur: FileNode) -> some View {
        let drawn = arcs.filter { $0.depth == 1 }
        let drawnNodes = drawn.compactMap(\.node)
        let small = drawn.first { if case .small = $0.kind { return true }; return false }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(cur === model.root ? model.target.title : cur.name).font(.title2.weight(.semibold)).lineLimit(1).truncationMode(.middle)
                Spacer()
                Text(centerTitle(cur)).font(.title2.weight(.medium).monospacedDigit())
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 8)

            List {
                ForEach(Array(drawnNodes.enumerated()), id: \.element.id) { i, n in
                    legendRow(dot: SunburstPalette.dot(index: n.isDirectory ? (arcIndex(for: n) ?? i) : -1, scheme: scheme), title: n.name, bytes: n.size, dimmedTitle: false)
                        .contentShape(Rectangle())
                        .onHover { inside in hovered = inside ? drawn.first { $0.node === n } : nil }
                        .onTapGesture { if n.isDirectory { zoomTo(n) } else { Trash.reveal(n.url) } }
                        .draggable(n.path)
                        .contextMenu { contextMenu(for: n) }
                        .listRowSeparator(.hidden)
                }
                if let s = small, case .small(let bytes, let items) = s.kind {
                    legendRow(dot: Color(white: scheme == .dark ? 0.4 : 0.75), title: "smaller objects…", bytes: bytes, dimmedTitle: true)
                        .contentShape(Rectangle())
                        .onHover { inside in hovered = inside ? s : nil }
                        .onTapGesture { showSmall = true }
                        .help("\(Format.count(items.count)) items too small to draw")
                        .listRowSeparator(.hidden)
                }
                if hiddenBytes > 0, cur.parent == nil {
                    legendRow(dot: SunburstPalette.color(index: -2, depth: 1, scheme: scheme), title: "hidden space…", bytes: hiddenBytes, dimmedTitle: false, tint: SunburstPalette.color(index: -2, depth: 1, scheme: scheme))
                        .contentShape(Rectangle())
                        .onHover { inside in hovered = inside ? arcs.first { if case .hidden = $0.kind { return true }; return false } : nil }
                        .help(model.hasFullDiskAccess ? "Used space the scan cannot read: other users, protected system data, local snapshots." : "Used space the scan cannot read. Grant Full Disk Access to see more of it.")
                        .listRowSeparator(.hidden)
                }
                if isWholeDisk, cur.parent == nil {
                    Divider().padding(.vertical, 4).listRowSeparator(.hidden)
                    legendRow(dot: Color(white: scheme == .dark ? 0.3 : 0.85), title: "free space", bytes: model.volume.available, dimmedTitle: true).listRowSeparator(.hidden)
                    HStack(spacing: 10) {
                        Text("~").font(.callout.weight(.bold)).foregroundStyle(.secondary).frame(width: 10)
                        Text("free + purgeable").font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        Text(Format.bytes(model.volume.availableImportant)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .background(scheme == .dark ? Color.black.opacity(0.18) : Color(nsColor: .windowBackgroundColor))
    }

    private func arcIndex(for n: FileNode) -> Int? { arcs.first { $0.depth == 1 && $0.node === n }?.colorIndex }

    private func legendRow(dot: Color, title: String, bytes: Int64, dimmedTitle: Bool, tint: Color? = nil) -> some View {
        HStack(spacing: 10) {
            Circle().fill(dot).frame(width: 9, height: 9)
            Text(title).font(.callout).foregroundStyle(tint ?? (dimmedTitle ? Color.secondary : Color.primary)).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            Text(Format.bytes(bytes)).font(.callout.monospacedDigit()).foregroundStyle(dimmedTitle ? .secondary : .primary)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func contextMenu(for n: FileNode) -> some View {
        if n.isDirectory { Button("Open in Map") { zoomTo(n) } }
        Button("Reveal in Finder") { Trash.reveal(n.url) }
        Button(model.collector.contains(n) ? "Remove from Collector" : "Add to Collector") { model.collector.toggle(n) }
        Divider()
        Button("Move to Trash…", role: .destructive) { model.collector.add(n); confirmTrash = true }
    }

    private func smallObjectsSheet(for cur: FileNode) -> some View {
        let items = arcs.compactMap { a -> [FileNode]? in if a.depth == 1, case .small(_, let i) = a.kind { return i }; return nil }.first ?? []
        return VStack(spacing: 0) {
            HStack {
                Text("Smaller objects in \(cur.name)").font(.headline)
                Spacer()
                Button("Done") { showSmall = false }.keyboardShortcut(.defaultAction)
            }
            .padding(14)
            Divider()
            List(items) { n in
                HStack {
                    Image(systemName: n.isDirectory ? "folder.fill" : "doc").foregroundStyle(.secondary).frame(width: 16)
                    Text(n.name).lineLimit(1)
                    Spacer()
                    Text(Format.bytes(n.size)).sizeStyle()
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { if n.isDirectory { showSmall = false; zoomTo(n) } }
                .contextMenu { contextMenu(for: n) }
            }
        }
        .frame(width: 520, height: 460)
    }

    // MARK: collector

    private var collectorZone: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().strokeBorder(dropTargeted ? Color.accentColor : Color.secondary.opacity(0.35), lineWidth: 2).frame(width: 46, height: 46)
                Circle().fill(model.collector.isEmpty ? Color.clear : Color.accentColor.opacity(0.25)).frame(width: 30, height: 30)
                if !model.collector.isEmpty { Text("\(model.collector.count)").font(.caption.weight(.bold)) }
            }
            if model.collector.isEmpty {
                Text("Drag and drop files here to collect them").font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(model.collector.count) item\(model.collector.count == 1 ? "" : "s") · \(Format.bytes(model.collector.total))").font(.callout.weight(.semibold))
                    Text(model.collector.nodes.prefix(3).map(\.name).joined(separator: ", ") + (model.collector.count > 3 ? "…" : "")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            if !model.collector.isEmpty {
                Button("Clear") { model.collector.clear() }
                Button("Move to Trash") { confirmTrash = true }.buttonStyle(.borderedProminent).disabled(trashing)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(dropTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
        .dropDestination(for: String.self) { paths, _ in
            var added = false
            for p in paths { if let n = find(path: p) { model.collector.add(n); added = true } }
            return added
        } isTargeted: { dropTargeted = $0 }
    }

    private func find(path: String) -> FileNode? {
        guard let root = model.root else { return nil }
        var found: FileNode? = nil
        root.walk { n in
            if found != nil { return false }
            if n.path == path { found = n; return false }
            return path.hasPrefix(n.path + "/") || n.parent == nil
        }
        return found
    }

    private func commitCollector() {
        let items = model.collector.nodes.map { ($0.url, $0.size) }
        trashing = true
        DispatchQueue.global(qos: .userInitiated).async {
            let r = Trash.move(items)
            DispatchQueue.main.async {
                trashing = false
                model.collector.clear()
                if !r.failures.isEmpty { model.lastError = r.failures.map { "\($0.0): \($0.1)" }.joined(separator: "\n") }
                model.volume = VolumeInfo.current()
                model.startScan(model.target)
            }
        }
    }
}
