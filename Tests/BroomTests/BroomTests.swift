import XCTest
@testable import Broom

final class BroomTests: XCTestCase {
    func testScannerMatchesDu() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("broom-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp.appendingPathComponent("a/b"), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 300_000).write(to: tmp.appendingPathComponent("a/one.bin"))
        try Data(repeating: 2, count: 120_000).write(to: tmp.appendingPathComponent("a/b/two.bin"))
        try Data(repeating: 3, count: 8_000).write(to: tmp.appendingPathComponent("three.bin"))
        // hardlink must not double count
        try FileManager.default.linkItem(at: tmp.appendingPathComponent("a/one.bin"), to: tmp.appendingPathComponent("link.bin"))
        // symlink must be ignored
        try FileManager.default.createSymbolicLink(at: tmp.appendingPathComponent("sym"), withDestinationURL: tmp.appendingPathComponent("a"))
        defer { try? FileManager.default.removeItem(at: tmp) }

        let root = BulkScanner().scan(path: tmp.path)
        XCTAssertEqual(root.fileCount, 3)
        // allocated size is block-rounded; compare with du -sk
        let du = Shell.run("/usr/bin/du", ["-sk", tmp.path]).split(separator: "\t").first.flatMap { Int64($0) } ?? -1
        XCTAssertEqual(root.size, du * 1024)
        XCTAssertTrue(root.children.map(\.size) == root.children.map(\.size).sorted(by: >))   // sorted by size desc
        XCTAssertTrue(root.children.allSatisfy { $0.name != "sym" })
    }

    func testSunburstLayoutCoversFullCircle() {
        let root = FileNode(name: "/r", isDirectory: true)
        let kids = (0..<5).map { FileNode(name: "f\($0)", isDirectory: false, size: Int64(($0 + 1) * 1000), parent: root) }
        root.attach(children: kids)
        let arcs = SunburstLayout.arcs(for: root)
        XCTAssertEqual(arcs.count, 5)
        let total = arcs.reduce(0.0) { $0 + $1.span }
        XCTAssertEqual(total, 2 * .pi, accuracy: 1e-9)
        XCTAssertEqual(arcs.first?.node?.name, "f4")
    }

    func testTinyItemsMerge() {
        let root = FileNode(name: "/r", isDirectory: true)
        var kids = [FileNode(name: "big", isDirectory: false, size: 1_000_000, parent: root)]
        // each tiny item is below the minimum angle, but together they are wide enough to draw
        kids += (0..<200).map { FileNode(name: "tiny\($0)", isDirectory: false, size: 1000, parent: root) }
        root.attach(children: kids)
        let arcs = SunburstLayout.arcs(for: root)
        XCTAssertEqual(arcs.count, 2)
        XCTAssertNil(arcs.last?.node)
    }

    func testCollectorDedupes() {
        let root = FileNode(name: "/r", isDirectory: true)
        let a = FileNode(name: "a", isDirectory: true, parent: root)
        let b = FileNode(name: "b", isDirectory: false, size: 10, parent: a)
        a.attach(children: [b]); root.attach(children: [a])
        var c = Collector()
        c.add(b); c.add(a)
        XCTAssertEqual(c.count, 1)
        XCTAssertTrue(c.contains(a))
        c.add(b)
        XCTAssertEqual(c.count, 1)
    }

    func testFormat() {
        XCTAssertEqual(Format.bytes(1_000_000_000), "1 GB")
        XCTAssertEqual(Format.percent(0.256), "26%")
    }
}
