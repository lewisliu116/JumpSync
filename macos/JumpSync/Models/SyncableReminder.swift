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

    /// Canonical content hash used for two-way reconcile. Normalizes whitespace so
    /// a value that has round-tripped through the server's markdown files hashes
    /// identically to the live EventKit value. Deliberately excludes `completionDate`
    /// (derived from `isCompleted`) and `id` (may be reassigned on server-side creation).
    var syncHash: String {
        func norm(_ s: String?) -> String {
            (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let parts = [norm(title), norm(notes), norm(dueDate), "\(priority)", norm(list), "\(isCompleted)"]
        return parts.joined(separator: "\u{1}").sha256()
    }
}
