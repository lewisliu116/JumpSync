import Foundation

/// Codable reminder model from remindctl JSON output
struct SyncableReminder: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var notes: String?
    var dueDate: String?
    var priority: Int
    var list: String
    var isCompleted: Bool
    var completionDate: String?
    var creationDate: String?
    var modificationDate: String?

    var slug: String {
        title.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "[^a-z0-9-]", with: "", options: .regularExpression)
            .prefix(60).description
    }

    var contentHash: String {
        let content = "\(title)\(notes ?? "")\(dueDate ?? "")\(priority)\(list)\(isCompleted)\(completionDate ?? "")"
        return content.sha256()
    }

    /// Canonical content hash used for two-way reconcile. Normalizes whitespace and
    /// due-date precision so a value that has round-tripped through the server's
    /// markdown files (and through EventKit) hashes identically to the live value.
    /// Deliberately excludes `completionDate` (derived from `isCompleted`) and `id`
    /// (may be reassigned on server-side creation).
    var syncHash: String {
        func norm(_ s: String?) -> String {
            (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let parts = [norm(title), norm(notes), Self.normalizedDueDate(dueDate), "\(priority)", norm(list), "\(isCompleted)"]
        return parts.joined(separator: "\u{1}").sha256()
    }

    /// Canonicalize a due date to whole-minute UTC precision. EventKit stores reminder
    /// due dates only to the minute, and different ISO-8601 spellings of the same instant
    /// (fractional seconds, `Z` vs offset) would otherwise hash differently and make a
    /// reminder look "changed" on every reconcile. Unparseable values hash as their
    /// trimmed raw string.
    static func normalizedDueDate(_ raw: String?) -> String {
        guard let s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return "" }
        let withFrac = ISO8601DateFormatter()
        withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        guard let date = withFrac.date(from: s) ?? plain.date(from: s) else { return s }
        let epochMinute = (date.timeIntervalSince1970 / 60).rounded(.down)
        return "m\(Int(epochMinute))"
    }
}
