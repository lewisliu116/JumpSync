import Foundation
import EventKit

/// Extracts reminders using Apple's native EventKit framework
class RemindersService {
    private let store = EKEventStore()
    private let dateFormatter: ISO8601DateFormatter

    init() {
        dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    /// Request access to Reminders
    func requestAccess() async throws -> Bool {
        if #available(macOS 14.0, *) {
            return try await store.requestFullAccessToReminders()
        } else {
            return try await store.requestAccess(to: .reminder)
        }
    }

    /// Fetch all reminders using EventKit
    func fetchAllReminders() async throws -> [SyncableReminder] {
        let granted = try await requestAccess()
        guard granted else {
            throw RemindersError.accessDenied
        }

        // Get all visible reminder calendars (lists)
        let calendars = store.calendars(for: .reminder)
        guard !calendars.isEmpty else { return [] }

        // Create a predicate to fetch only INCOMPLETE reminders across all lists
        // Note: passing nil for both dates fetches all active reminders without date bounds
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: calendars)

        return try await withCheckedThrowingContinuation { continuation in
            store.fetchReminders(matching: predicate) { ekReminders in
                guard let ekReminders = ekReminders else {
                    continuation.resume(returning: [])
                    return
                }

                let syncable = ekReminders.map { self.convert($0) }
                continuation.resume(returning: syncable)
            }
        }
    }

    /// Listen for background changes to the EventStore (create/update/delete/complete)
    func observeChanges(_ handler: @escaping () -> Void) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { _ in
            handler()
        }
    }

    // MARK: - Conversion

    private func convert(_ r: EKReminder) -> SyncableReminder {
        var dueDateStr: String?
        if let due = r.dueDateComponents?.date {
            dueDateStr = dateFormatter.string(from: due)
        }

        var completionDateStr: String?
        if let compDate = r.completionDate {
            completionDateStr = dateFormatter.string(from: compDate)
        }

        var creationDateStr: String?
        if let createDate = r.creationDate {
            creationDateStr = dateFormatter.string(from: createDate)
        }

        var modDateStr: String?
        if let modDate = r.lastModifiedDate {
            modDateStr = dateFormatter.string(from: modDate)
        }

        return SyncableReminder(
            id: r.calendarItemIdentifier,
            title: r.title,
            notes: r.hasNotes ? r.notes : nil,
            dueDate: dueDateStr,
            priority: r.priority,
            list: r.calendar.title,
            isCompleted: r.isCompleted,
            completionDate: completionDateStr,
            creationDate: creationDateStr,
            modificationDate: modDateStr
        )
    }
}

enum RemindersError: Error, LocalizedError {
    case accessDenied

    var errorDescription: String? {
        switch self {
        case .accessDenied: return "Reminders access denied. Enable in System Settings → Privacy & Security → Reminders."
        }
    }
}
