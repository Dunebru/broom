import Foundation
import SwiftUI

// `Broom --scan-cli PATH` runs the scanner headless and prints totals, used for benchmarking and tests.
if let i = CommandLine.arguments.firstIndex(of: "--scan-cli"), CommandLine.arguments.count > i + 1 {
    let path = CommandLine.arguments[i + 1]
    let scanner = BulkScanner()
    let start = Date()
    let root = scanner.scan(path: path)
    let secs = Date().timeIntervalSince(start)
    print("\(path): \(Format.bytes(root.size)) in \(Format.count(root.fileCount)) files, \(String(format: "%.2f", secs)) s")
    for c in root.children.prefix(12) {
        print(String(format: "  %10@  %@%@", Format.bytes(c.size), c.name, c.isDirectory ? "/" : ""))
    }
    exit(0)
}

BroomApp.main()
