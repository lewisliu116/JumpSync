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

        // Fetch ALL reminders (complete + incomplete) across all lists. Including
        // completed items is required for two-way sync so completion state can
        // round-trip instead of a completed reminder looking like a deletion.
        let predicate = store.predicateForReminders(in: calendars)

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

    // MARK: - Write-back (two-way sync)

    /// Create or update a reminder in EventKit from a synced value.
    /// Returns the resulting `calendarItemIdentifier` — newly assigned by EventKit
    /// when the item is created, so callers can reconcile server-side placeholder IDs.
    @discardableResult
    func applyUpsert(_ r: SyncableReminder) throws -> String {
        let reminder: EKReminder
        if let existing = store.calendarItem(withIdentifier: r.id) as? EKReminder {
            reminder = existing
        } else {
            reminder = EKReminder(eventStore: store)
            reminder.calendar = calendar(forListNamed: r.list)
        }

        reminder.title = r.title
        reminder.notes = r.notes
        if (0...9).contains(r.priority) {
            reminder.priority = r.priority
        }

        if let dueStr = r.dueDate, let due = parseDate(dueStr) {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: due)
        } else {
            reminder.dueDateComponents = nil
        }

        // Assigning isCompleted manages completionDate automatically.
        reminder.isCompleted = r.isCompleted

        try store.save(reminder, commit: true)
        return reminder.calendarItemIdentifier
    }

    /// Delete a reminder from EventKit by identifier. No-op if it no longer exists.
    func applyDelete(id: String) throws {
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
        try store.remove(reminder, commit: true)
    }

    private func calendar(forListNamed name: String) -> EKCalendar? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let match = store.calendars(for: .reminder).first(where: {
            $0.title.caseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            return match
        }
        return store.defaultCalendarForNewReminders() ?? store.calendars(for: .reminder).first
    }

    private func parseDate(_ s: String) -> Date? {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFractional.date(from: s) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: s)
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
