import SwiftUI
import Observation

/// Central app state — drives UI and sync coordination
@MainActor
@Observable
class AppState {
    // MARK: - Navigation
    var selectedTab: SidebarTab = .summary

    // MARK: - Sync Status
    var isSyncing = false
    var lastSyncDate: Date?
    var contactCount: Int = 0
    var reminderCount: Int = 0
    var noteCount: Int = 0

    var contactStatus: SourceStatus = .idle
    var reminderStatus: SourceStatus = .idle
    var noteStatus: SourceStatus = .idle

    // MARK: - History
    var syncHistory: [SyncLogEntry] = []

    // MARK: - Configuration
    var config = AppConfiguration.load()

    // MARK: - Menu Bar Icon
    var menuBarIcon: String {
        if isSyncing { return "arrow.triangle.2.circlepath" }
        if contactStatus == .error || reminderStatus == .error || noteStatus == .error {
            return "exclamationmark.icloud"
        }
        return "icloud.and.arrow.up"
    }

    // MARK: - Services
    private var _syncCoordinator: SyncCoordinator?
    var syncCoordinator: SyncCoordinator {
        if _syncCoordinator == nil {
            _syncCoordinator = SyncCoordinator(appState: self)
        }
        return _syncCoordinator!
    }

    // MARK: - Actions
    func triggerSync() {
        Task { @MainActor in
            await syncCoordinator.syncAll()
        }
    }

    func addLogEntry(_ entry: SyncLogEntry) {
        syncHistory.insert(entry, at: 0)
        if syncHistory.count > 500 {
            syncHistory = Array(syncHistory.prefix(500))
        }
    }
}

// MARK: - Supporting Types

enum SidebarTab: String, CaseIterable, Identifiable {
    case summary = "Summary"
    case configuration = "Configuration"
    case history = "History"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .summary: return "house.fill"
        case .configuration: return "gearshape.fill"
        case .history: return "clock.fill"
        }
    }
}

enum SourceStatus: String {
    case idle = "Idle"
    case syncing = "Syncing"
    case synced = "Synced"
    case warning = "Warning"
    case error = "Error"

    var color: Color {
        switch self {
        case .idle: return .gray
        case .syncing: return .blue
        case .synced: return .green
        case .warning: return .yellow
        case .error: return .red
        }
    }
}
