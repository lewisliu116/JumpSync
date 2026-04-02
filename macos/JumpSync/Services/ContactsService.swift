import Foundation
@preconcurrency import Contacts

/// Extracts all contacts using Apple's native Contacts framework
final class ContactsService: @unchecked Sendable {
    private let store = CNContactStore()

    /// Request access to Contacts
    func requestAccess() async throws -> Bool {
        try await store.requestAccess(for: .contacts)
    }

    /// Fetch all contacts with all available fields
    func fetchAllContacts() async throws -> [SyncableContact] {
        let granted = try await requestAccess()
        guard granted else {
            throw ContactsError.accessDenied
        }

        let keysToFetch: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactJobTitleKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactPostalAddressesKey as CNKeyDescriptor,
            CNContactBirthdayKey as CNKeyDescriptor,
            CNContactSocialProfilesKey as CNKeyDescriptor,
            CNContactUrlAddressesKey as CNKeyDescriptor,
            CNContactImageDataKey as CNKeyDescriptor,
            CNContactDatesKey as CNKeyDescriptor,
            CNContactDepartmentNameKey as CNKeyDescriptor,
            CNContactInstantMessageAddressesKey as CNKeyDescriptor,
        ]

        let request = CNContactFetchRequest(keysToFetch: keysToFetch)
        request.sortOrder = .givenName

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .background).async {
                do {
                    var contacts: [SyncableContact] = []
                    try self.store.enumerateContacts(with: request) { cnContact, _ in
                        let contact = Self.convert(cnContact)
                        contacts.append(contact)
                    }
                    continuation.resume(returning: contacts)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Subscribe to contact store changes
    func observeChanges(_ handler: @escaping () -> Void) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(
            forName: .CNContactStoreDidChange,
            object: nil,
            queue: .main
        ) { _ in
            handler()
        }
    }

    // MARK: - Conversion

    private static func convert(_ cn: CNContact) -> SyncableContact {
        let emails = cn.emailAddresses.map {
            LabeledValue(
                label: CNLabeledValue<NSString>.localizedString(forLabel: $0.label ?? "other"),
                value: $0.value as String
            )
        }

        let phones = cn.phoneNumbers.map {
            LabeledValue(
                label: CNLabeledValue<CNPhoneNumber>.localizedString(forLabel: $0.label ?? "other"),
                value: $0.value.stringValue
            )
        }

        let addresses = cn.postalAddresses.map { labeled -> LabeledAddress in
            let addr = labeled.value
            return LabeledAddress(
                label: CNLabeledValue<CNPostalAddress>.localizedString(forLabel: labeled.label ?? "other"),
                street: addr.street,
                city: addr.city,
                state: addr.state,
                postalCode: addr.postalCode,
                country: addr.country
            )
        }

        let socialProfiles = cn.socialProfiles.map {
            LabeledValue(
                label: $0.value.service,
                value: $0.value.username
            )
        }

        let urls = cn.urlAddresses.map {
            LabeledValue(
                label: CNLabeledValue<NSString>.localizedString(forLabel: $0.label ?? "other"),
                value: $0.value as String
            )
        }

        var birthday: String?
        if let bday = cn.birthday {
            var components = bday
            components.calendar = Calendar.current
            if let date = components.date {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                birthday = formatter.string(from: date)
            }
        }

        var imageBase64: String?
        if let imageData = cn.imageData {
            imageBase64 = imageData.base64EncodedString()
        }

        return SyncableContact(
            id: cn.identifier,
            givenName: cn.givenName,
            familyName: cn.familyName,
            organizationName: cn.organizationName,
            jobTitle: cn.jobTitle,
            emailAddresses: emails,
            phoneNumbers: phones,
            postalAddresses: addresses,
            birthday: birthday,
            note: nil, // Note field requires com.apple.developer.contacts.notes entitlement
            socialProfiles: socialProfiles,
            urlAddresses: urls,
            imageDataBase64: imageBase64,
            modifiedAt: nil
        )
    }
}

enum ContactsError: Error, LocalizedError {
    case accessDenied

    var errorDescription: String? {
        switch self {
        case .accessDenied: return "Contacts access denied. Enable in System Settings → Privacy & Security → Contacts."
        }
    }
}
