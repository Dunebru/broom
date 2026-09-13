import Foundation

public enum Format {
    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file   // Finder-style: 1 GB = 1000^3
        f.allowsNonnumericFormatting = false
        return f
    }()

    public static func bytes(_ n: Int64) -> String { byteFormatter.string(fromByteCount: n) }

    public static func count(_ n: Int) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? String(n)
    }

    public static func relativeDate(_ d: Date?) -> String {
        guard let d else { return "-" }
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .short
        return f.localizedString(for: d, relativeTo: Date())
    }

    public static func percent(_ v: Double) -> String {
        String(format: "%.0f%%", v * 100)
    }
}
