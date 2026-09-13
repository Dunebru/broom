import Foundation

/// Time Machine local (APFS) snapshots. They are "purgeable" in theory, but macOS often keeps them
/// for 24 h and they can hold tens of gigabytes hostage after large deletions.
struct LocalSnapshot: Identifiable, Hashable {
    let id: String     // full name, e.g. com.apple.TimeMachine.2026-09-13-120000.local
    let date: Date?

    var stamp: String {
        // tmutil wants the "2026-09-13-120000" part
        let comps = id.split(separator: ".")
        return comps.count >= 4 ? String(comps[3]) : id
    }

    static func list() -> [LocalSnapshot] {
        let out = Shell.run("/usr/bin/tmutil", ["listlocalsnapshots", "/"])
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd-HHmmss"; f.timeZone = .current
        return out.split(separator: "\n").compactMap { line in
            let s = line.trimmingCharacters(in: .whitespaces)
            guard s.hasPrefix("com.apple.TimeMachine.") else { return nil }
            let snap = LocalSnapshot(id: s, date: nil)
            return LocalSnapshot(id: s, date: f.date(from: snap.stamp))
        }
    }

    /// Delete one snapshot. Needs administrator rights, so macOS shows a password prompt.
    static func delete(_ snapshot: LocalSnapshot) -> String? {
        Shell.runAsAdmin("/usr/bin/tmutil deletelocalsnapshots \(snapshot.stamp)")
    }

    /// Ask macOS to purge as many local snapshots as it can.
    static func thinAll() -> String? {
        Shell.runAsAdmin("/usr/bin/tmutil thinlocalsnapshots / 9999999999999 4")
    }
}

enum Shell {
    static func run(_ launchPath: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    /// Runs a command with administrator privileges via the system authorization dialog.
    /// Returns nil on success or an error message.
    static func runAsAdmin(_ command: String) -> String? {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escaped)\" with administrator privileges"
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int
            if code == -128 { return "Canceled" }
            return (error[NSAppleScript.errorMessage] as? String) ?? "Failed"
        }
        return nil
    }
}
