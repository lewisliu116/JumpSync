import Foundation

/// State for a single synced item
struct SyncItemState: Codable {
    let hash: String
    let relativePath: String
}

/// Persistent sync state — tracks what has been synced via content hashes and filenames
struct SyncState: Codable {
    var contactHashes: [String: SyncItemState] = [:]  // id → state
    var reminderHashes: [String: SyncItemState] = [:]
    var noteHashes: [String: SyncItemState] = [:]
    var lastSyncDate: Date?

    // MARK: - Persistence

    private static var fileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("JumpSync", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("sync_state.json")
    }

    static func load() -> SyncState {
        guard let data = try? Data(contentsOf: fileURL),
              let state = try? JSONDecoder().decode(SyncState.self, from: data) else {
            return SyncState()
        }
        return state
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self) else { return }
        try? data.write(to: SyncState.fileURL)
    }
}
