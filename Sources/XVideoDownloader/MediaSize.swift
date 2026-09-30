import Foundation

enum MediaSize {
    enum Unit: String {
        case kilobytes = "KB"
        case megabytes = "MB"

        var bytes: Double { self == .kilobytes ? 1_000 : 1_000_000 }
    }

    static func targetBytes(text: String, unit: Unit) throws -> Int64? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return nil }
        guard let value = Double(text), value.isFinite, value > 0 else {
            throw MediaCompressionError.invalidTarget
        }
        let bytes = (value * unit.bytes).rounded(.down)
        guard bytes.isFinite, bytes >= 1, bytes < Double(Int64.max) else {
            throw MediaCompressionError.invalidTarget
        }
        return Int64(bytes)
    }

    static func format(_ bytes: Int64, unit: Unit? = nil) -> String {
        let unit = unit ?? (bytes < 1_000_000 ? .kilobytes : .megabytes)
        return String(format: "%.2f %@", locale: Locale(identifier: "en_US_POSIX"), Double(bytes) / unit.bytes, unit.rawValue)
    }
}
