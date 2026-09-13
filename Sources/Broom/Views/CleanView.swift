import SwiftUI

struct CleanView: View {
    @EnvironmentObject private var model: AppModel
    @State private var expanded: Set<String> = []
    @State private var confirm = false
    @State private var cleaning = false
    @State private var lastResult: String?

    var body: some View {
        if model.isAnalyzingJunk && model.junk.isEmpty {
            VStack(spacing: 12) { ProgressView().controlSize(.large); Text("Looking for junk…").foregroundStyle(.secondary) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.junk.isEmpty {
            EmptyStateView(symbol: "sparkles", title: "Nothing to clean", message: "No caches, logs, installers or old backups worth removing were found.", action: { model.analyzeJunk() }, actionTitle: "Check Again")
        } else {
            VStack(spacing: 0) {
                List {
                    ForEach(model.junk) { cat in categoryRow(cat) }
                }
                .listStyle(.inset)
                footer
            }
            .confirmationDialog("Clean \(Format.bytes(model.selectedJunkBytes))?", isPresented: $confirm, titleVisibility: .visible) {
                Button("Clean", role: .destructive) { clean() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Caches and logs are deleted permanently (they regenerate). Installers and backups go to the Trash.")
            }
            .alert("Done", isPresented: Binding(get: { lastResult != nil }, set: { if !$0 { lastResult = nil } })) {
                Button("OK") { lastResult = nil }
            } message: { Text(lastResult ?? "") }
        }
    }

    private func categoryRow(_ cat: JunkCategory) -> some View {
        let isOpen = expanded.contains(cat.id)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Toggle("", isOn: Binding(get: { cat.allSelected }, set: { on in setAll(cat.id, on) }))
                    .toggleStyle(.checkbox).labelsHidden()
                Image(systemName: cat.symbol).font(.title3).foregroundStyle(cat.risk == .caution ? Color.orange : Color.accentColor).frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(cat.name).font(.callout.weight(.semibold))
                        if cat.risk == .caution { Text("REVIEW").font(.caption2.weight(.bold)).padding(.horizontal, 5).padding(.vertical, 1).background(.orange.opacity(0.18), in: Capsule()).foregroundStyle(.orange) }
                        Text(cat.mode == .trash ? "to Trash" : "permanent").font(.caption2).foregroundStyle(.tertiary)
                    }
                    Text(cat.explanation).font(.caption).foregroundStyle(.secondary).lineLimit(isOpen ? nil : 2)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Format.bytes(cat.selectedSize)).font(.callout.weight(.semibold).monospacedDigit())
                    if cat.selectedSize != cat.size { Text("of \(Format.bytes(cat.size))").font(.caption2).foregroundStyle(.tertiary) }
                }
                Button { withAnimation(.snappy) { if isOpen { expanded.remove(cat.id) } else { expanded.insert(cat.id) } } } label: {
                    Image(systemName: "chevron.right").rotationEffect(.degrees(isOpen ? 90 : 0)).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.snappy) { if isOpen { expanded.remove(cat.id) } else { expanded.insert(cat.id) } } }

            if isOpen {
                VStack(spacing: 0) {
                    ForEach(cat.items.prefix(200)) { item in
                        HStack(spacing: 10) {
                            Toggle("", isOn: Binding(get: { item.selected }, set: { on in set(cat.id, item.id, on) })).toggleStyle(.checkbox).labelsHidden()
                            Text(item.name).font(.callout).lineLimit(1).truncationMode(.middle)
                            if let note = item.note { Text(note).font(.caption2).foregroundStyle(.orange) }
                            Spacer()
                            Text(Format.relativeDate(item.modified)).font(.caption).foregroundStyle(.tertiary)
                            Text(Format.bytes(item.size)).sizeStyle().frame(width: 80, alignment: .trailing)
                            Button { Trash.reveal(item.url) } label: { Image(systemName: "magnifyingglass") }.buttonStyle(.plain).foregroundStyle(.secondary).help("Reveal in Finder")
                        }
                        .padding(.leading, 42).padding(.vertical, 3)
                    }
                    if cat.items.count > 200 { Text("\(cat.items.count - 200) more…").font(.caption).foregroundStyle(.tertiary).padding(.leading, 42) }
                }
                .padding(.bottom, 6)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button { model.analyzeJunk() } label: { Label("Rescan", systemImage: "arrow.clockwise") }.disabled(model.isAnalyzingJunk)
            if model.isAnalyzingJunk { ProgressView().controlSize(.small) }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(Format.bytes(model.selectedJunkBytes)).font(.title2.weight(.bold).monospacedDigit())
                Text("selected for removal").font(.caption).foregroundStyle(.secondary)
            }
            Button(cleaning ? "Cleaning…" : "Clean") { confirm = true }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(cleaning || model.selectedJunkBytes == 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func setAll(_ cat: String, _ on: Bool) {
        guard let i = model.junk.firstIndex(where: { $0.id == cat }) else { return }
        for j in model.junk[i].items.indices { model.junk[i].items[j].selected = on }
    }

    private func set(_ cat: String, _ item: String, _ on: Bool) {
        guard let i = model.junk.firstIndex(where: { $0.id == cat }), let j = model.junk[i].items.firstIndex(where: { $0.id == item }) else { return }
        model.junk[i].items[j].selected = on
    }

    private func clean() {
        cleaning = true
        let plan = model.junk.map { ($0.mode, $0.items.filter(\.selected).map { ($0.url, $0.size) }) }
        DispatchQueue.global(qos: .userInitiated).async {
            var freed: Int64 = 0; var count = 0; var failures: [String] = []
            for (mode, items) in plan where !items.isEmpty {
                let r = mode == .trash ? Trash.move(items) : Trash.remove(items)
                freed += r.bytes; count += r.moved
                failures += r.failures.map { "\(URL(fileURLWithPath: $0.0).lastPathComponent): \($0.1)" }
            }
            DispatchQueue.main.async {
                cleaning = false
                var msg = "Removed \(count) item\(count == 1 ? "" : "s"), freeing \(Format.bytes(freed))."
                if !failures.isEmpty { msg += "\n\nCould not remove:\n" + failures.prefix(8).joined(separator: "\n") }
                lastResult = msg
                model.volume = VolumeInfo.current()
                model.analyzeJunk()
            }
        }
    }
}
