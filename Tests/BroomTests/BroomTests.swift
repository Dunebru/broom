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

final class SunburstMorphTests: XCTestCase {
    func testZoomInMapsChosenFolderOntoFullCircle() {
        let root = FileNode(name: "/r", isDirectory: true)
        let a = FileNode(name: "a", isDirectory: true, parent: root)
        let b = FileNode(name: "b", isDirectory: true, parent: root)
        let a1 = FileNode(name: "a1", isDirectory: false, size: 300, parent: a)
        let a2 = FileNode(name: "a2", isDirectory: false, size: 100, parent: a)
        let b1 = FileNode(name: "b1", isDirectory: false, size: 600, parent: b)
        a.attach(children: [a1, a2]); b.attach(children: [b1]); root.attach(children: [a, b])
        let outer = SunburstLayout.arcs(for: root)
        let inner = SunburstLayout.arcs(for: a)
        let tx = MorphTransform.between(from: outer, fromRoot: root, to: inner, toRoot: a)
        XCTAssertNotNil(tx)
        guard let tx else { return }
        XCTAssertTrue(tx.zoomIn)
        let arcA = outer.first { $0.node === a }!
        let (d, s, e) = tx.target(depth: Double(arcA.depth), start: arcA.start, end: arcA.end)
        XCTAssertEqual(d, 0, accuracy: 1e-9)
        XCTAssertEqual(s, 0, accuracy: 1e-9)
        XCTAssertEqual(e, 2 * .pi, accuracy: 1e-9)
        // a1 sits at depth 2 in the outer map and depth 1 in the inner map; source() must recover the outer place.
        let innerA1 = inner.first { $0.node === a1 }!
        let outerA1 = outer.first { $0.node === a1 }!
        let (d0, s0, e0) = tx.source(depth: Double(innerA1.depth), start: innerA1.start, end: innerA1.end)
        XCTAssertEqual(d0, Double(outerA1.depth), accuracy: 1e-9)
        XCTAssertEqual(s0, outerA1.start, accuracy: 1e-9)
        XCTAssertEqual(e0, outerA1.end, accuracy: 1e-9)
        // b lives outside the zoomed folder, so it leaves the circle.
        let arcB = outer.first { $0.node === b }!
        let (_, sb, eb) = tx.target(depth: Double(arcB.depth), start: arcB.start, end: arcB.end)
        XCTAssertTrue(eb <= 1e-9 || sb >= 2 * .pi - 1e-9, "b should be pushed outside the circle")
        // Zooming back out is the inverse.
        let back = MorphTransform.between(from: inner, fromRoot: a, to: outer, toRoot: root)!
        XCTAssertFalse(back.zoomIn)
        let (d2, s2, e2) = back.target(depth: Double(innerA1.depth), start: innerA1.start, end: innerA1.end)
        XCTAssertEqual(d2, Double(outerA1.depth), accuracy: 1e-9)
        XCTAssertEqual(s2, outerA1.start, accuracy: 1e-9)
        XCTAssertEqual(e2, outerA1.end, accuracy: 1e-9)
    }
}
