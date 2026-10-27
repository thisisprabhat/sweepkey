import Foundation

/// Formatting helpers shared with the `cleaner` command-line tool.
public enum CLIFormatting {
    /// Parses "100MB", "1.5 GB", "2g", "512" (bytes) into a byte count using 1024-based units.
    /// Returns nil for malformed or negative input.
    public static func parseSize(_ text: String) -> Int64? {
        let s = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !s.isEmpty else { return nil }
        let numberChars = CharacterSet(charactersIn: "0123456789.")
        var numberPart = ""
        var unitPart = ""
        for ch in s.unicodeScalars {
            if unitPart.isEmpty, numberChars.contains(ch) { numberPart.unicodeScalars.append(ch) }
            else if ch == " " , unitPart.isEmpty { continue }
            else { unitPart.unicodeScalars.append(ch) }
        }
        guard !numberPart.isEmpty, let value = Double(numberPart), value.isFinite else { return nil }
        let multiplier: Double
        switch unitPart {
        case "", "b": multiplier = 1
        case "k", "kb", "kib": multiplier = 1_024
        case "m", "mb", "mib": multiplier = 1_048_576
        case "g", "gb", "gib": multiplier = 1_073_741_824
        case "t", "tb", "tib": multiplier = 1_099_511_627_776
        default: return nil
        }
        let bytes = value * multiplier
        guard bytes < Double(Int64.max) else { return nil }
        return Int64(bytes.rounded())
    }

    /// Human-readable size such as "1.5 GB" (1024-based).
    public static func formatBytes(_ bytes: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(max(bytes, 0))
        var unit = 0
        while value >= 1024, unit < units.count - 1 {
            value /= 1024
            unit += 1
        }
        return unit == 0 ? "\(Int(value)) B" : String(format: "%.1f %@", value, units[unit])
    }

    /// Compact relative date such as "3d ago"; "-" when nil.
    public static func formatAge(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "-" }
        let seconds = max(0, now.timeIntervalSince(date))
        let days = Int(seconds / 86_400)
        if days >= 365 { return "\(days / 365)y ago" }
        if days >= 30 { return "\(days / 30)mo ago" }
        if days >= 1 { return "\(days)d ago" }
        let hours = Int(seconds / 3600)
        if hours >= 1 { return "\(hours)h ago" }
        return "today"
    }

    /// Renders an aligned text table. Columns listed in `rightAligned` are right-aligned.
    public static func table(headers: [String], rows: [[String]], rightAligned: Set<Int> = []) -> String {
        let columns = headers.count
        var widths = headers.map(\.count)
        for row in rows {
            for (i, cell) in row.prefix(columns).enumerated() { widths[i] = max(widths[i], cell.count) }
        }
        func render(_ cells: [String]) -> String {
            (0..<columns).map { i in
                let cell = i < cells.count ? cells[i] : ""
                let pad = String(repeating: " ", count: max(0, widths[i] - cell.count))
                if rightAligned.contains(i) { return pad + cell }
                return i == columns - 1 ? cell : cell + pad
            }.joined(separator: "  ")
        }
        var lines = [render(headers), widths.map { String(repeating: "-", count: $0) }.joined(separator: "  ")]
        lines += rows.map(render)
        return lines.joined(separator: "\n")
    }
}
