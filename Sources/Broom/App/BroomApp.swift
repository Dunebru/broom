import SwiftUI

struct BroomApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("Broom") {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 640)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("View") {
                ForEach(Array(Pane.allCases.enumerated()), id: \.element) { i, pane in
                    Button(pane.rawValue) { model.section = pane }.keyboardShortcut(KeyEquivalent(Character(String(i + 1))), modifiers: .command)
                }
            }
            CommandMenu("Scan") {
                Button("Scan Home Folder") { model.startScan(.home) }.keyboardShortcut("r")
                Button("Scan Whole Disk") { model.startScan(.disk) }.keyboardShortcut("R")
                Button("Stop Scan") { model.cancelScan() }.keyboardShortcut(".").disabled(!model.isScanning)
            }
        }
        Settings { SettingsView().environmentObject(model) }
    }
}
