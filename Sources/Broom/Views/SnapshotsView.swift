import SwiftUI

struct SnapshotsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StatCard(title: "What these are", symbol: "info.circle") {
                Text("Time Machine keeps hourly snapshots of your disk for 24 hours so you can restore files even when the backup drive is unplugged. macOS calls them purgeable, but after big deletions they often keep gigabytes locked up for a day. Deleting them only affects local restore points, never your backup drive.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                Text("Purgeable right now: \(Format.bytes(model.volume.purgeable))").font(.callout.weight(.medium))
                Spacer()
                Button { refresh() } label: { Label("Refresh", systemImage: "arrow.clockwise") }.disabled(working)
                Button("Delete All Snapshots") { thinAll() }.buttonStyle(.borderedProminent).disabled(working || model.snapshots.isEmpty)
            }
            if model.snapshots.isEmpty {
                EmptyStateView(symbol: "clock.arrow.circlepath", title: "No local snapshots", message: "Nothing is being held. Snapshots reappear as Time Machine runs; check back after large deletions.")
            } else {
                List(model.snapshots) { s in
                    HStack {
                        Image(systemName: "clock").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(s.date.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? s.stamp).font(.callout)
                            Text(s.id).font(.caption).foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Text(Format.relativeDate(s.date)).font(.caption).foregroundStyle(.secondary)
                        Button("Delete") { delete(s) }.disabled(working)
                    }
                }
                .listStyle(.inset)
            }
            Text("Deleting asks for your password because tmutil needs administrator rights. Free space can take a minute to update.").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(20)
    }

    private func refresh() {
        working = true
        DispatchQueue.global().async {
            let s = LocalSnapshot.list(); let v = VolumeInfo.current()
            DispatchQueue.main.async { model.snapshots = s; model.volume = v; working = false }
        }
    }

    private func delete(_ s: LocalSnapshot) {
        working = true
        DispatchQueue.global().async {
            let err = LocalSnapshot.delete(s)
            DispatchQueue.main.async { if let err, err != "Canceled" { model.lastError = err }; refresh() }
        }
    }

    private func thinAll() {
        working = true
        DispatchQueue.global().async {
            let err = LocalSnapshot.thinAll()
            DispatchQueue.main.async { if let err, err != "Canceled" { model.lastError = err }; refresh() }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        Form {
            LabeledContent("Full Disk Access") {
                HStack {
                    Image(systemName: model.hasFullDiskAccess ? "checkmark.circle.fill" : "xmark.circle").foregroundStyle(model.hasFullDiskAccess ? .green : .secondary)
                    Text(model.hasFullDiskAccess ? "Granted" : "Not granted")
                    Button("Open System Settings") { FullDiskAccess.openSettings() }
                    Button("Re-check") { model.refreshAccess() }
                }
            }
            Text("Broom never deletes anything without a confirmation. Caches and logs are removed permanently because they regenerate; everything else goes to the Trash.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 460)
    }
}
