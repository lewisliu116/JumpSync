import Foundation

/// Codable contact model for syncing
struct SyncableContact: Codable, Identifiable, Hashable {
    let id: String
    var givenName: String
    var familyName: String
    var organizationName: String
    var jobTitle: String
    var emailAddresses: [LabeledValue]
    var phoneNumbers: [LabeledValue]
    var postalAddresses: [LabeledAddress]
    var birthday: String?
    var note: String?
    var socialProfiles: [LabeledValue]
    var urlAddresses: [LabeledValue]
    var imageDataBase64: String?
    var modifiedAt: Date?

    var fullName: String {
        "\(givenName) \(familyName)".trimmingCharacters(in: .whitespaces)
    }

    var slug: String {
        fullName.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "[^a-z0-9-]", with: "", options: .regularExpression)
    }

    /// SHA-256 content hash for change detection
    var contentHash: String {
        let content = "\(givenName)\(familyName)\(organizationName)\(jobTitle)" +
            "\(emailAddresses)\(phoneNumbers)\(postalAddresses)" +
            "\(birthday ?? "")\(note ?? "")\(socialProfiles)\(urlAddresses)"
        return content.sha256()
    }
}

struct LabeledValue: Codable, Hashable {
    let label: String
    let value: String
}

struct LabeledAddress: Codable, Hashable {
    let label: String
    let street: String
    let city: String
    let state: String
    let postalCode: String
    let country: String

    var formatted: String {
        [street, city, state, postalCode, country]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

// MARK: - String hashing extension

import CryptoKit

extension String {
    func sha256() -> String {
        let data = Data(self.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}
