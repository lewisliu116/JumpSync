import Foundation

/// Stub API client for remote mode (Phase 6)
class APIClient {
    private let session = URLSession.shared

    var baseURL: String = ""
    var apiKey: String = ""

    init(config: AppConfiguration) {
        var base = config.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") {
            base.removeLast()
        }
        self.baseURL = base
        self.apiKey = config.apiKey
    }

    /// Health check
    func healthCheck() async throws -> Bool {
        let url = URL(string: "\(baseURL)/api/health")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await session.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    struct SyncPayload<T: Encodable>: Encodable {
        let changed: [T]
        let deleted: [String]
    }

    /// Bulk sync contacts
    func syncContacts(changed: [SyncableContact], deleted: [String]) async throws {
        let payload = SyncPayload(changed: changed, deleted: deleted)
        try await postJSON(path: "/api/sync/contacts", body: payload)
    }

    /// Bulk sync reminders
    func syncReminders(changed: [SyncableReminder], deleted: [String]) async throws {
        let payload = SyncPayload(changed: changed, deleted: deleted)
        try await postJSON(path: "/api/sync/reminders", body: payload)
    }

    /// A reminder as stored on the server, plus the server-side last-modified
    /// timestamp (file mtime) used to break two-way conflicts.
    struct RemoteReminder: Decodable {
        let id: String
        var title: String
        var notes: String?
        var dueDate: String?
        var priority: Int?
        var list: String?
        var isCompleted: Bool
        var completionDate: String?
        var creationDate: String?
        var modificationDate: String?
        var serverModified: String?

        var asSyncable: SyncableReminder {
            SyncableReminder(
                id: id,
                title: title,
                notes: notes,
                dueDate: dueDate,
                priority: priority ?? 0,
                list: list ?? "Reminders",
                isCompleted: isCompleted,
                completionDate: completionDate,
                creationDate: creationDate,
                modificationDate: modificationDate
            )
        }
    }

    private struct ReminderPullResponse: Decodable {
        let reminders: [RemoteReminder]
    }

    /// Pull all reminders currently stored on the server (two-way sync).
    func pullReminders() async throws -> [RemoteReminder] {
        let response: ReminderPullResponse = try await getJSON(path: "/api/sync/reminders")
        return response.reminders
    }

    /// Bulk sync notes
    func syncNotes(changed: [SyncableNote], deleted: [String]) async throws {
        let payload = SyncPayload(changed: changed, deleted: deleted)
        try await postJSON(path: "/api/sync/notes", body: payload)
    }

    // MARK: - Private

    private func getJSON<R: Decodable>(path: String) async throws -> R {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try JSONDecoder().decode(R.self, from: data)
    }

    private func postJSON<T: Encodable>(path: String, body: T) async throws {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }
}

enum APIError: Error, LocalizedError {
    case invalidURL
    case serverError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid server URL"
        case .serverError(let code): return "Server error (HTTP \(code))"
        }
    }
}
