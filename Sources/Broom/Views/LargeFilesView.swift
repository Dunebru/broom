import SwiftUI

struct LargeFilesView: View {
    @EnvironmentObject private var model: AppModel
    @State private var minSize: Int64 = 100_000_000
    @State private var olderThanMonths: Int = 0
    @State private var selection = Set<FileNode.ID>()
    @State private var confirm = false

    private var files: [FileNode] {
        guard let root = model.root else { return [] }
        var out: [FileNode] = []
        let cutoff = olderThanMonths > 0 ? Calendar.current.date(byAdding: .month, value: -olderThanMonths, to: Date()) : nil
        root.walk { n in
            if n.isDirectory { return n.size >= minSize }   // prune small subtrees
            if n.size >= minSize, cutoff == nil || (n.modified ?? .distantPast) < cutoff! { out.append(n) }
            return false
        }
        return out.sorted { $0.size > $1.size }
    }

    private func nodes(_ ids: Set<FileNode.ID>) -> [FileNode] { files.filter { ids.contains($0.id) } }

    var body: some View {
        if model.root == nil {
            EmptyStateView(symbol: "doc.zipper", title: "Scan first", message: "Large files are found in the scan results. Scan your home folder or the whole disk.", action: { model.startScan(.home) }, actionTitle: "Scan Home Folder")
        } else {
            VStack(spacing: 0) {
                HStack {
                    Picker("Larger than", selection: $minSize) {
                        Text("50 MB").tag(Int64(50_000_000)); Text("100 MB").tag(Int64(100_000_000)); Text("500 MB").tag(Int64(500_000_000)); Text("1 GB").tag(Int64(1_000_000_000))
                    }.frame(width: 190)
                    Picker("Unchanged for", selection: $olderThanMonths) {
                        Text("Any time").tag(0); Text("1 month").tag(1); Text("6 months").tag(6); Text("1 year").tag(12)
                    }.frame(width: 200)
                    Spacer()
                    Text("\(files.count) files · \(Format.bytes(files.reduce(0) { $0 + $1.size }))").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                Divider()
                Table(files, selection: $selection) {
                    TableColumn("Name") { f in
                        HStack(spacing: 6) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: f.path)).resizable().frame(width: 16, height: 16)
                            Text(f.name).lineLimit(1)
                        }
                    }
                    TableColumn("Size") { f in Text(Format.bytes(f.size)).monospacedDigit() }.width(90)
                    TableColumn("Modified") { f in Text(Format.relativeDate(f.modified)).foregroundStyle(.secondary) }.width(110)
                    TableColumn("Location") { f in Text(f.parent?.path ?? "").foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }
                }
                .contextMenu(forSelectionType: FileNode.ID.self) { ids in
                    Button("Reveal in Finder") { nodes(ids).forEach { Trash.reveal($0.url) } }
                    Button("Move to Trash…", role: .destructive) { selection = ids; confirm = true }
                }
                HStack {
                    Text("Files are moved to the Trash, nothing is deleted permanently here.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Move \(selection.count) to Trash") { confirm = true }.buttonStyle(.borderedProminent).disabled(selection.isEmpty)
                }
                .padding(.horizontal, 16).padding(.vertical, 10).background(.bar).overlay(alignment: .top) { Divider() }
            }
            .confirmationDialog("Move \(selection.count) file\(selection.count == 1 ? "" : "s") (\(Format.bytes(nodes(selection).reduce(0) { $0 + $1.size }))) to the Trash?", isPresented: $confirm, titleVisibility: .visible) {
                Button("Move to Trash", role: .destructive) {
                    let items = nodes(selection).map { ($0.url, $0.size) }
                    selection.removeAll()
                    DispatchQueue.global().async {
                        let r = Trash.move(items)
                        DispatchQueue.main.async {
                            if !r.failures.isEmpty { model.lastError = r.failures.map { "\($0.0): \($0.1)" }.joined(separator: "\n") }
                            model.startScan(model.target)
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}
