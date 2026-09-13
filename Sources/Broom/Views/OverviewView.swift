import Charts
import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var model: AppModel

    private struct Slice: Identifiable { let id: String; let bytes: Int64; let color: Color }

    private var slices: [Slice] {
        let v = model.volume
        return [
            Slice(id: "Used", bytes: v.used - v.purgeable, color: .accentColor),
            Slice(id: "Purgeable", bytes: v.purgeable, color: .orange.opacity(0.75)),
            Slice(id: "Free", bytes: v.available, color: Color(nsColor: .quaternaryLabelColor)),
        ].filter { $0.bytes > 0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 18) {
                    donut
                    VStack(alignment: .leading, spacing: 12) {
                        Text(model.volume.name).font(.title2.weight(.bold))
                        legendRow("Used", model.volume.used - model.volume.purgeable, .accentColor)
                        legendRow("Purgeable (snapshots, caches macOS may drop)", model.volume.purgeable, .orange.opacity(0.75))
                        legendRow("Free", model.volume.available, Color(nsColor: .quaternaryLabelColor))
                        Divider().padding(.vertical, 2)
                        if !model.hasFullDiskAccess {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Full Disk Access is off").font(.callout.weight(.semibold))
                                    Text("Mail, Safari and Time Machine data stay hidden and totals run lower than Finder. Grant it in System Settings, then reopen Broom.").font(.caption).foregroundStyle(.secondary)
                                    Button("Open System Settings") { FullDiskAccess.openSettings() }.controlSize(.small).padding(.top, 2)
                                }
                            } icon: { Image(systemName: "lock.shield").foregroundStyle(.orange) }
                        } else {
                            Label("Full Disk Access granted", systemImage: "checkmark.shield").font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 12) {
                    StatCard(title: "Cleanable now", symbol: "sparkles") {
                        if model.isAnalyzingJunk {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(Format.bytes(model.selectedJunkBytes)).font(.title.weight(.bold).monospacedDigit())
                            Text("\(model.junk.count) categories · safe defaults selected").font(.caption).foregroundStyle(.secondary)
                            Button("Review & Clean") { model.section = .clean }.buttonStyle(.borderedProminent).controlSize(.regular).padding(.top, 2)
                        }
                    }
                    StatCard(title: "App leftovers", symbol: "app.dashed") {
                        Text(Format.bytes(model.leftovers.reduce(0) { $0 + $1.size })).font(.title.weight(.bold).monospacedDigit())
                        Text("\(model.leftovers.count) uninstalled apps left data behind").font(.caption).foregroundStyle(.secondary)
                        Button("Review") { model.section = .apps }.controlSize(.regular).padding(.top, 2)
                    }
                    StatCard(title: "Local snapshots", symbol: "clock.arrow.circlepath") {
                        Text("\(model.snapshots.count)").font(.title.weight(.bold).monospacedDigit())
                        Text(model.snapshots.isEmpty ? "None, nothing held hostage" : "Time Machine keeps up to 24 h locally").font(.caption).foregroundStyle(.secondary)
                        Button("Manage") { model.section = .snapshots }.controlSize(.regular).padding(.top, 2)
                    }
                }

                StatCard(title: "Storage map", symbol: "chart.pie") {
                    if let root = model.root {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(model.target.title), \(Format.bytes(root.size)) in \(Format.count(root.fileCount)) files").font(.callout.weight(.medium))
                                Text("Scanned in \(String(format: "%.1f", model.scanDuration)) s").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Explore") { model.section = .map }
                        }
                        ForEach(root.children.prefix(6)) { c in
                            HStack {
                                Image(systemName: c.isDirectory ? "folder.fill" : "doc").foregroundStyle(.secondary).frame(width: 16)
                                Text(c.name).lineLimit(1)
                                Spacer()
                                Text(Format.bytes(c.size)).sizeStyle()
                            }
                            SizeBar(fraction: Double(c.size) / Double(max(1, root.size)))
                        }
                    } else if model.isScanning {
                        ProgressView(value: nil as Double?) { Text("Scanning \(model.target.title)… \(Format.count(model.progress.files)) files").font(.callout) }
                    } else {
                        HStack {
                            Text("See exactly where your space went, folder by folder.").font(.callout).foregroundStyle(.secondary)
                            Spacer()
                            Button("Scan Home Folder") { model.startScan(.home) }.buttonStyle(.borderedProminent)
                            Button("Whole Disk") { model.startScan(.disk) }
                        }
                    }
                }
            }
            .padding(20)
        }
        .onAppear { model.refreshAccess() }
    }

    private var donut: some View {
        Chart(slices) { s in
            SectorMark(angle: .value("Bytes", Double(s.bytes)), innerRadius: .ratio(0.68), angularInset: 1.5)
                .cornerRadius(4)
                .foregroundStyle(s.color)
        }
        .chartLegend(.hidden)
        .frame(width: 180, height: 180)
        .overlay {
            VStack(spacing: 0) {
                Text(Format.percent(model.volume.usedFraction)).font(.title.weight(.bold).monospacedDigit())
                Text("used").font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel("\(Format.percent(model.volume.usedFraction)) of disk used")
    }

    private func legendRow(_ title: String, _ bytes: Int64, _ color: Color) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(title).font(.callout)
            Spacer()
            Text(Format.bytes(bytes)).sizeStyle()
        }
    }
}
