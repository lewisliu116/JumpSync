import Foundation

/// Represents a sync log entry for the History view
struct SyncLogEntry: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let source: SyncSource
    let type: SyncEventType
    let message: String

    init(source: SyncSource, type: SyncEventType, message: String) {
        self.id = UUID()
        self.timestamp = Date()
        self.source = source
        self.type = type
        self.message = message
    }
}

enum SyncSource: String, CaseIterable, Codable {
    case contacts = "Contacts"
    case reminders = "Reminders"
    case notes = "Notes"
    case system = "System"

    var icon: String {
        switch self {
        case .contacts: return "person.2.fill"
        case .reminders: return "checklist"
        case .notes: return "note.text"
        case .system: return "gear"
        }
    }
}

enum SyncEventType: String, Codable {
    case fullSync = "Full Sync"
    case incremental = "Incremental"
    case error = "Error"
    case warning = "Warning"
    case info = "Info"

    var dotColor: String {
        switch self {
        case .fullSync: return "blue"
        case .incremental: return "green"
        case .error: return "red"
        case .warning: return "yellow"
        case .info: return "gray"
        }
    }
}
