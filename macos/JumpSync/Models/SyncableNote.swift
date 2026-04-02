import Foundation

struct SyncableAttachment: Codable, Identifiable, Hashable {
    let id: String
    let filename: String
    let mimeType: String
    let base64Data: String
}

/// Codable note model from memo CLI output
struct SyncableNote: Codable, Identifiable, Hashable {
    let id: String
    var title: String
    var body: String
    var folder: String
    var tags: [String]?
    var attachments: [SyncableAttachment]?
    var creationDate: String?
    var modificationDate: String?

    var slug: String {
        title.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "[^a-z0-9-]", with: "", options: .regularExpression)
            .prefix(60).description
    }

    var contentHash: String {
        let tagStr = tags?.joined(separator: "") ?? ""
        let attachStr = attachments?.map { "\($0.id)\($0.base64Data.count)" }.joined() ?? ""
        let content = "\(title)\(body)\(folder)\(modificationDate ?? "")\(tagStr)\(attachStr)"
        return content.sha256()
    }
}
