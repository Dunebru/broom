import SwiftUI

/// One ring segment of the map.
struct Arc: Identifiable {
    enum Kind { case item(FileNode), small(bytes: Int64, items: [FileNode]), hidden(bytes: Int64) }
    let id: Int
    let kind: Kind
    let depth: Int            // 1 = innermost ring
    let start: Double         // radians, clockwise from 12 o'clock
    let end: Double
    let colorIndex: Int       // top-level palette slot this segment belongs to (-1 = file/gray, -2 = hidden)
    var span: Double { end - start }
    var node: FileNode? { if case .item(let n) = kind { return n }; return nil }
    var bytes: Int64 {
        switch kind {
        case .item(let n): n.size
        case .small(let b, _): b
        case .hidden(let b): b
        }
    }
}

enum SunburstPalette {
    // DaisyDisk-like: green, blue, violet, magenta, yellow, cyan, orange, red, teal, pink, lime, indigo
    static let hues: [Double] = [0.30, 0.62, 0.72, 0.85, 0.15, 0.52, 0.08, 0.00, 0.45, 0.92, 0.22, 0.66]

    static func color(index: Int, depth: Int, scheme: ColorScheme, highlighted: Bool = false, dimmed: Bool = false) -> Color {
        let op = dimmed ? 0.3 : 1.0
        if index == -2 { return Color(hue: 0.78, saturation: 0.55, brightness: scheme == .dark ? 0.75 : 0.7).opacity(op) }
        if index < 0 {  // file: gray, lighter with depth
            let base = scheme == .dark ? 0.40 : 0.72
            return Color(white: base + Double(depth - 1) * 0.05 + (highlighted ? 0.12 : 0)).opacity(op)
        }
        let hue = hues[index % hues.count]
        let d = Double(depth - 1)
        let sat = max(0.25, (highlighted ? 0.9 : 0.72) - d * 0.09)
        let bri = min(1, (scheme == .dark ? 0.82 : 0.88) + d * 0.03 + (highlighted ? 0.08 : 0))
        return Color(hue: hue, saturation: sat, brightness: bri).opacity(op)
    }

    static func dot(index: Int, scheme: ColorScheme) -> Color {
        index == -1 ? Color(white: scheme == .dark ? 0.55 : 0.6) : color(index: index, depth: 1, scheme: scheme)
    }
}

enum SunburstLayout {
    static let maxDepth = 6
    static let minAngle = 0.4 * .pi / 180

    /// - Parameters:
    ///   - root: folder at the center
    ///   - usedFraction: share of the full circle the root occupies (1 = full circle; for a whole-disk
    ///     scan it is scannedBytes / capacity so the empty gap reads as free space)
    ///   - hiddenBytes: space used on the volume that the scan could not see; drawn as a violet petal
    static func arcs(for root: FileNode, usedFraction: Double = 1, hiddenBytes: Int64 = 0, capacity: Int64 = 0) -> [Arc] {
        var out: [Arc] = []
        var nextID = 0
        let total = Double(max(1, root.size))
        let rootSpan = 2 * .pi * min(1, max(0, usedFraction))

        func layout(_ node: FileNode, depth: Int, start: Double, end: Double, colorIndex: Int?) {
            guard depth <= maxDepth, node.size > 0, end - start >= minAngle else { return }
            let nodeTotal = Double(node.size)
            var cursor = start
            var smallStart: Double? = nil
            var smallBytes: Int64 = 0
            var smallItems: [FileNode] = []
            for (i, child) in node.children.enumerated() {
                let span = (end - start) * Double(child.size) / nodeTotal
                let idx = child.isDirectory ? (colorIndex ?? i) : -1
                if span >= minAngle {
                    out.append(Arc(id: nextID, kind: .item(child), depth: depth, start: cursor, end: cursor + span, colorIndex: idx)); nextID += 1
                    if child.isDirectory { layout(child, depth: depth + 1, start: cursor, end: cursor + span, colorIndex: colorIndex ?? i) }
                } else {
                    if smallStart == nil { smallStart = cursor }
                    smallBytes += child.size; smallItems.append(child)
                }
                cursor += span
            }
            if let s = smallStart, cursor - s >= minAngle / 6 {
                out.append(Arc(id: nextID, kind: .small(bytes: smallBytes, items: smallItems), depth: depth, start: s, end: cursor, colorIndex: colorIndex ?? -1)); nextID += 1
            }
        }
        layout(root, depth: 1, start: 0, end: rootSpan, colorIndex: nil)
        if hiddenBytes > 0, capacity > 0 {
            let span = 2 * .pi * Double(hiddenBytes) / Double(capacity)
            out.append(Arc(id: nextID, kind: .hidden(bytes: hiddenBytes), depth: 1, start: rootSpan, end: rootSpan + span, colorIndex: -2)); nextID += 1
        }
        _ = total
        return out
    }
}

/// How one layout maps onto the next when the map zooms. Zooming into a segment stretches that
/// segment over the full circle and moves its children one ring inward; zooming out is the inverse.
struct MorphTransform {
    /// Angular window of the zoomed segment in the outer layout, and its ring depth.
    var start: Double
    var end: Double
    var depth: Int
    /// Root span of the inner layout (a full circle, or less for a whole-disk root).
    var innerSpan: Double
    /// True when the new layout is inside the old one (zoom in), false when zooming out.
    var zoomIn: Bool

    /// Geometry (depth, start, end) of an outer-layout arc expressed in inner-layout coordinates.
    func toInner(depth: Double, start: Double, end: Double) -> (Double, Double, Double) {
        let w = max(self.end - self.start, 1e-9)
        return (depth - Double(self.depth), (start - self.start) / w * innerSpan, (end - self.start) / w * innerSpan)
    }

    /// Geometry of an inner-layout arc expressed in outer-layout coordinates.
    func toOuter(depth: Double, start: Double, end: Double) -> (Double, Double, Double) {
        let w = self.end - self.start
        return (depth + Double(self.depth), self.start + start / innerSpan * w, self.start + end / innerSpan * w)
    }

    /// Where an arc from the previous layout ends up.
    func target(depth: Double, start: Double, end: Double) -> (Double, Double, Double) {
        zoomIn ? toInner(depth: depth, start: start, end: end) : toOuter(depth: depth, start: start, end: end)
    }

    /// Where an arc from the next layout comes from.
    func source(depth: Double, start: Double, end: Double) -> (Double, Double, Double) {
        zoomIn ? toOuter(depth: depth, start: start, end: end) : toInner(depth: depth, start: start, end: end)
    }

    static func rootSpan(of arcs: [Arc]) -> Double {
        let ends = arcs.filter { $0.depth == 1 && $0.colorIndex != -2 }.map(\.end)
        return ends.max() ?? 2 * .pi
    }

    /// Build the transform for going from `from` (showing `fromRoot`) to `to` (showing `toRoot`).
    static func between(from: [Arc], fromRoot: FileNode, to: [Arc], toRoot: FileNode) -> MorphTransform? {
        if toRoot.isDescendant(of: fromRoot), let a = from.first(where: { $0.node === toRoot }) {
            return MorphTransform(start: a.start, end: a.end, depth: a.depth, innerSpan: rootSpan(of: to), zoomIn: true)
        }
        if fromRoot.isDescendant(of: toRoot), let a = to.first(where: { $0.node === fromRoot }) {
            return MorphTransform(start: a.start, end: a.end, depth: a.depth, innerSpan: rootSpan(of: from), zoomIn: false)
        }
        return nil
    }
}

/// Identity of an arc across layouts: the node for real items, otherwise the parent plus kind.
private func arcKey(_ a: Arc) -> String {
    switch a.kind {
    case .item(let n): return "n\(n.id)"
    case .small(_, let items): return "s\(items.first?.parent?.id ?? -1)"
    case .hidden: return "h"
    }
}

/// The ring drawing, animatable between two layouts. `progress` runs 0 to 1 while SwiftUI
/// interpolates it, and every frame draws each arc somewhere between its old and new place.
struct SunburstCanvas: View, Animatable {
    var from: [Arc]
    var to: [Arc]
    var transform: MorphTransform?
    var progress: Double
    var hovered: Arc?
    var hole: Double
    var ring: Double
    var center: CGPoint
    var scheme: ColorScheme

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    private struct Drawn {
        var depth: Double
        var start: Double
        var end: Double
        var colorIndex: Int
        var isSmall: Bool
        var opacity: Double
        var hover: Bool
        var kin: Bool
        var oldColorIndex: Int?
    }

    var body: some View {
        Canvas(rendersAsynchronously: true) { ctx, _ in
            var track = Path()
            track.addArc(center: center, radius: hole + ring - 1, startAngle: .zero, endAngle: .degrees(360), clockwise: false)
            track.addArc(center: center, radius: hole + 1, startAngle: .degrees(360), endAngle: .zero, clockwise: true)
            ctx.fill(track, with: .color(scheme == .dark ? .white.opacity(0.05) : .black.opacity(0.04)))

            for d in drawn() {
                guard d.opacity > 0.01 else { continue }
                let startA = max(0, d.start), endA = min(2 * .pi, d.end)
                guard endA - startA > 0.0005 else { continue }
                let inner = max(hole + 1, hole + ring * (d.depth - 1) + 1)
                let outer = min(hole + ring * Double(SunburstLayout.maxDepth) - 1, hole + ring * d.depth - 1)
                guard outer > inner else { continue }
                var path = Path()
                path.addArc(center: center, radius: outer, startAngle: .radians(startA - .pi / 2), endAngle: .radians(endA - .pi / 2), clockwise: false)
                path.addArc(center: center, radius: inner, startAngle: .radians(endA - .pi / 2), endAngle: .radians(startA - .pi / 2), clockwise: true)
                path.closeSubpath()
                let hi = d.hover || d.kin
                let dim = hovered != nil && !hi
                let depthInt = max(1, Int(d.depth.rounded()))
                func paint(_ index: Int) -> Color {
                    let c = SunburstPalette.color(index: index, depth: depthInt, scheme: scheme, highlighted: hi, dimmed: dim)
                    return d.isSmall ? c.opacity(dim ? 0.2 : 0.45) : c
                }
                if let old = d.oldColorIndex, old != d.colorIndex, progress < 1 {
                    ctx.fill(path, with: .color(paint(old).opacity(d.opacity * (1 - progress))))
                    ctx.fill(path, with: .color(paint(d.colorIndex).opacity(d.opacity * progress)))
                } else {
                    ctx.fill(path, with: .color(paint(d.colorIndex).opacity(d.opacity)))
                }
                if endA - startA > 0.015 {
                    ctx.stroke(path, with: .color((scheme == .dark ? Color.black.opacity(0.45) : Color.white.opacity(0.9)).opacity(d.opacity)), lineWidth: 0.8)
                }
            }
        }
    }

    private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

    private func drawn() -> [Drawn] {
        let t = min(1, max(0, progress))
        var hoverNode: FileNode? = hovered?.node
        if hovered != nil, hoverNode == nil { hoverNode = nil }
        func kin(_ a: Arc) -> Bool {
            guard let hn = hoverNode, let n = a.node else { return false }
            return n === hn || n.isDescendant(of: hn)
        }
        if t >= 1 || from.isEmpty {
            return to.map { Drawn(depth: Double($0.depth), start: $0.start, end: $0.end, colorIndex: $0.colorIndex,
                                  isSmall: { if case .small = $0.kind { return true }; return false }($0),
                                  opacity: 1, hover: hovered?.id == $0.id, kin: kin($0), oldColorIndex: nil) }
        }
        let fromByKey = Dictionary(from.map { (arcKey($0), $0) }, uniquingKeysWith: { a, _ in a })
        let toKeys = Set(to.map(arcKey))
        var out: [Drawn] = []
        out.reserveCapacity(from.count + to.count)
        for b in to {
            let key = arcKey(b)
            let isSmall: Bool = { if case .small = b.kind { return true }; return false }()
            if let a = fromByKey[key] {
                out.append(Drawn(depth: lerp(Double(a.depth), Double(b.depth), t), start: lerp(a.start, b.start, t), end: lerp(a.end, b.end, t),
                                 colorIndex: b.colorIndex, isSmall: isSmall, opacity: 1, hover: hovered?.id == b.id, kin: kin(b), oldColorIndex: a.colorIndex))
            } else if let tr = transform {
                let (d0, s0, e0) = tr.source(depth: Double(b.depth), start: b.start, end: b.end)
                out.append(Drawn(depth: lerp(d0, Double(b.depth), t), start: lerp(s0, b.start, t), end: lerp(e0, b.end, t),
                                 colorIndex: b.colorIndex, isSmall: isSmall, opacity: t, hover: hovered?.id == b.id, kin: kin(b), oldColorIndex: nil))
            } else {
                out.append(Drawn(depth: Double(b.depth), start: b.start, end: b.end, colorIndex: b.colorIndex, isSmall: isSmall, opacity: t, hover: false, kin: false, oldColorIndex: nil))
            }
        }
        for a in from where !toKeys.contains(arcKey(a)) {
            let isSmall: Bool = { if case .small = a.kind { return true }; return false }()
            if let tr = transform {
                let (d1, s1, e1) = tr.target(depth: Double(a.depth), start: a.start, end: a.end)
                out.append(Drawn(depth: lerp(Double(a.depth), d1, t), start: lerp(a.start, s1, t), end: lerp(a.end, e1, t),
                                 colorIndex: a.colorIndex, isSmall: isSmall, opacity: 1 - t, hover: false, kin: false, oldColorIndex: nil))
            } else {
                out.append(Drawn(depth: Double(a.depth), start: a.start, end: a.end, colorIndex: a.colorIndex, isSmall: isSmall, opacity: 1 - t, hover: false, kin: false, oldColorIndex: nil))
            }
        }
        // Outgoing arcs first so incoming ones paint over them.
        return out.sorted { $0.opacity < $1.opacity }
    }
}

struct SunburstView: View {
    let root: FileNode
    let arcs: [Arc]
    var previousArcs: [Arc] = []
    var transform: MorphTransform? = nil
    var progress: Double = 1
    let centerTitle: String
    @Binding var hovered: Arc?
    var onSelect: (FileNode) -> Void
    var onUp: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var pointer: CGPoint? = nil
    private let holeRatio = 0.22

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = size / 2 - 8
            let hole = radius * holeRatio
            let ring = (radius - hole) / Double(SunburstLayout.maxDepth)

            ZStack {
                SunburstCanvas(from: previousArcs, to: arcs, transform: transform, progress: progress,
                               hovered: hovered, hole: hole, ring: ring, center: center, scheme: scheme)
                .drawingGroup()

                VStack(spacing: 1) {
                    Text(centerTitle).font(.system(size: max(12, hole / 3.2), weight: .semibold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.6)
                    if root.parent != nil {
                        Text(root.name).font(.system(size: max(9, hole / 7))).foregroundStyle(.secondary).lineLimit(1)
                        Image(systemName: "chevron.up").font(.system(size: max(8, hole / 9), weight: .semibold)).foregroundStyle(.tertiary)
                    }
                }
                .frame(width: hole * 1.7, height: hole * 1.7)
                .contentShape(Circle())
                .onTapGesture { onUp() }
                .position(center)
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let p): pointer = p; hovered = hitTest(p, center: center, hole: hole, ring: ring)
                case .ended: pointer = nil; hovered = nil
                }
            }
            .onTapGesture {
                if let p = pointer, let a = hitTest(p, center: center, hole: hole, ring: ring), let n = a.node, n.isDirectory { onSelect(n) }
            }
            .overlay(alignment: .topLeading) {
                if let a = hovered, let p = pointer {
                    tooltip(for: a)
                        .offset(x: min(p.x + 16, geo.size.width - 250), y: min(p.y + 16, geo.size.height - 64))
                        .allowsHitTesting(false)
                }
            }
        }
        .accessibilityLabel("Storage map of \(root.path), \(Format.bytes(root.size))")
    }

    private func isKinOfHovered(_ a: Arc) -> Bool {
        guard let h = hovered, let hn = h.node, let n = a.node else { return false }
        return n === hn || n.isDescendant(of: hn)
    }

    private func hitTest(_ p: CGPoint, center: CGPoint, hole: Double, ring: Double) -> Arc? {
        let dx = p.x - center.x, dy = p.y - center.y
        let r = sqrt(dx * dx + dy * dy)
        guard r >= hole else { return nil }
        let depth = Int((r - hole) / ring) + 1
        guard depth >= 1, depth <= SunburstLayout.maxDepth else { return nil }
        var angle = atan2(dy, dx) + .pi / 2
        if angle < 0 { angle += 2 * .pi }
        return arcs.first { $0.depth == depth && angle >= $0.start && angle < $0.end }
    }

    private func tooltip(for a: Arc) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            switch a.kind {
            case .item(let n):
                Text(n.name).font(.callout.weight(.semibold)).lineLimit(1)
                Text("\(Format.bytes(n.size)) · \(Format.percent(Double(n.size) / Double(max(1, root.size)))) of \(root.parent == nil ? "scanned" : root.name)").font(.caption).foregroundStyle(.secondary)
                if n.isDirectory { Text("\(Format.count(n.fileCount)) files").font(.caption2).foregroundStyle(.tertiary) }
            case .small(let b, let items):
                Text("Smaller objects").font(.callout.weight(.semibold))
                Text("\(Format.count(items.count)) items · \(Format.bytes(b))").font(.caption).foregroundStyle(.secondary)
            case .hidden(let b):
                Text("Hidden space").font(.callout.weight(.semibold))
                Text("\(Format.bytes(b)) used but not visible to this scan").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
        .frame(maxWidth: 240, alignment: .leading)
    }
}
