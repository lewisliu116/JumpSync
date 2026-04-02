import Foundation

/// Codable reminder model from remindctl JSON output
struct SyncableReminder: Codable, Identifiable, Hashable {
    let id: String
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
}
