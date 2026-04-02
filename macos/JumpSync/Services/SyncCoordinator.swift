import Foundation

/// Orchestrates sync across all data sources with scheduling
@MainActor
class SyncCoordinator {
    private weak var appState: AppState?
    private let contactsService = ContactsService()
    private let remindersService = RemindersService()
    // MARK: Unused - Keep original NotesService for AppleScript fallback if needed
    // private let notesService = NotesService()
    private let sqliteNotesService = SQLiteNotesService()
    private let markdownWriter = MarkdownWriter()
    private var syncState = SyncState.load()
    private var timer: Timer?
    private var contactsObserver: NSObjectProtocol?
    private var remindersObserver: NSObjectProtocol?

    init(appState: AppState) {
        self.appState = appState
        setupScheduledSync()
        setupContactsObserver()
    }

    deinit {
        timer?.invalidate()
        if let observer = contactsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = remindersObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Scheduling

    private func setupScheduledSync() {
        guard let appState else { return }
        let interval = appState.config.syncIntervalMinutes
        guard interval > 0 else { return }

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(interval * 60), repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                Task { @MainActor [weak self] in
                    await self?.syncAll()
                }
            }
        }
    }

    private func setupContactsObserver() {
        contactsObserver = contactsService.observeChanges { [weak self] in
            DispatchQueue.main.async {
                Task { @MainActor [weak self] in
                    await self?.syncContacts()
                }
            }
        }
        remindersObserver = remindersService.observeChanges { [weak self] in
            DispatchQueue.main.async {
                Task { @MainActor [weak self] in
                    await self?.syncReminders()
                }
            }
        }
    }

    // MARK: - Sync All

    func syncAll() async {
        guard let appState, !appState.isSyncing else { return }

        appState.isSyncing = true
        log(.system, .info, "Starting full sync…")

        // Sync each enabled source
        if appState.config.contactsEnabled {
            await syncContacts()
        }
        if appState.config.remindersEnabled {
            await syncReminders()
        }
        if appState.config.notesEnabled {
            await syncNotes()
        }

        appState.lastSyncDate = Date()
        appState.isSyncing = false
        syncState.lastSyncDate = Date()
        syncState.save()

        log(.system, .fullSync, "Full sync completed — \(appState.contactCount) contacts, \(appState.reminderCount) reminders, \(appState.noteCount) notes")
    }

    // MARK: - Per-Source Sync

    func syncContacts() async {
        guard let appState else { return }
        appState.contactStatus = .syncing

        do {
            let contacts = try await contactsService.fetchAllContacts()
            appState.contactCount = contacts.count

            let changes = detectChanges(items: contacts, existingHashes: syncState.contactHashes)

            if !changes.changed.isEmpty || !changes.deleted.isEmpty {
                let config = appState.config
                if config.outputMode == .local {
                    var pathsToDelete: [String] = []
                    for id in changes.deleted {
                        if let state = syncState.contactHashes[id] { pathsToDelete.append(state.relativePath) }
                    }
                    for item in changes.changed {
                        if let state = syncState.contactHashes["\(item.id)"] { pathsToDelete.append(state.relativePath) }
                    }
                    markdownWriter.deleteFiles(relativePaths: pathsToDelete, baseURL: config.localFolderURL)

                    let writtenPaths = try markdownWriter.writeContacts(changes.changed, to: config.localFolderURL)
                    log(.contacts, .incremental, "Contacts — Wrote \(writtenPaths.count) files, cleaned up \(pathsToDelete.count) old files")
                    
                    for (id, path) in writtenPaths {
                        if let hash = changes.changed.first(where: { "\($0.id)" == id })?.contentHash {
                            syncState.contactHashes[id] = SyncItemState(hash: hash, relativePath: path)
                        }
                    }
                }
                
                if config.outputMode == .remote {
                    let apiClient = APIClient(config: config)
                    try await apiClient.syncContacts(changed: changes.changed, deleted: changes.deleted)
                    log(.contacts, .incremental, "Contacts — Pushed \(changes.changed.count) changed, \(changes.deleted.count) deleted to Remote")
                    
                    for item in changes.changed {
                        syncState.contactHashes["\(item.id)"] = SyncItemState(hash: item.contentHash, relativePath: "")
                    }
                }

                for id in changes.deleted {
                    syncState.contactHashes.removeValue(forKey: id)
                }
                syncState.save()
            } else {
                log(.contacts, .info, "Contacts — No changes detected")
            }

            // Purge orphans on every run to guarantee perfect file system mirroring
            if appState.config.outputMode == .local {
                let permitted = Set(syncState.contactHashes.values.map(\.relativePath))
                markdownWriter.purgeOrphans(permittedRelativePaths: permitted, category: "contacts", baseURL: appState.config.localFolderURL)
            }

            appState.contactStatus = .synced
        } catch {
            appState.contactStatus = .error
            log(.contacts, .error, "Contacts — \(String(describing: error))")
        }
    }

    func syncReminders() async {
        guard let appState else { return }
        appState.reminderStatus = .syncing

        do {
            let reminders = try await remindersService.fetchAllReminders()
            appState.reminderCount = reminders.count

            let changes = detectChanges(items: reminders, existingHashes: syncState.reminderHashes)

            if !changes.changed.isEmpty || !changes.deleted.isEmpty {
                let config = appState.config
                if config.outputMode == .local {
                    var pathsToDelete: [String] = []
                    for id in changes.deleted {
                        if let state = syncState.reminderHashes[id] { pathsToDelete.append(state.relativePath) }
                    }
                    for item in changes.changed {
                        if let state = syncState.reminderHashes["\(item.id)"] { pathsToDelete.append(state.relativePath) }
                    }
                    markdownWriter.deleteFiles(relativePaths: pathsToDelete, baseURL: config.localFolderURL)

                    let writtenPaths = try markdownWriter.writeReminders(changes.changed, to: config.localFolderURL)
                    log(.reminders, .incremental, "Reminders — Wrote \(writtenPaths.count) files, cleaned up \(pathsToDelete.count) old files")
                    
                    for (id, path) in writtenPaths {
                        if let hash = changes.changed.first(where: { "\($0.id)" == id })?.contentHash {
                            syncState.reminderHashes[id] = SyncItemState(hash: hash, relativePath: path)
                        }
                    }
                }
                
                if config.outputMode == .remote {
                    let apiClient = APIClient(config: config)
                    try await apiClient.syncReminders(changed: changes.changed, deleted: changes.deleted)
                    log(.reminders, .incremental, "Reminders — Pushed \(changes.changed.count) changed, \(changes.deleted.count) deleted to Remote")
                    
                    for item in changes.changed {
                        syncState.reminderHashes["\(item.id)"] = SyncItemState(hash: item.contentHash, relativePath: "")
                    }
                }

                for id in changes.deleted {
                    syncState.reminderHashes.removeValue(forKey: id)
                }
                syncState.save()
            } else {
                log(.reminders, .info, "Reminders — No changes detected")
            }

            if appState.config.outputMode == .local {
                let permitted = Set(syncState.reminderHashes.values.map(\.relativePath))
                markdownWriter.purgeOrphans(permittedRelativePaths: permitted, category: "reminders", baseURL: appState.config.localFolderURL)
            }

            appState.reminderStatus = .synced
        } catch {
            appState.reminderStatus = .error
            log(.reminders, .error, "Reminders — \(String(describing: error))")
        }
    }

    func syncNotes() async {
        guard let appState else { return }
        appState.noteStatus = .syncing

        do {
            // let fetchResult = try await notesService.fetchAllNotes()
            let fetchResult = try await sqliteNotesService.fetchAllNotes(scriptURL: URL(fileURLWithPath: "/Users/liuxiao/Workspace/MacCloudSync/macos/Scripts/notes_exporter.sh")) { msg in
                DispatchQueue.main.async { [weak self] in
                    self?.log(.notes, .info, "Bridge: \(msg)")
                }
            }
            let notes = fetchResult.notes
            appState.noteCount = notes.count
            
            if fetchResult.skipped > 0 {
                log(.notes, .warning, "Notes — Blocked: skipped \(fetchResult.skipped) locked/unreadable notes")
            }

            let changes = detectChanges(items: notes, existingHashes: syncState.noteHashes)

            if !changes.changed.isEmpty || !changes.deleted.isEmpty {
                let config = appState.config
                if config.outputMode == .local {
                    var pathsToDelete: [String] = []
                    for id in changes.deleted {
                        if let state = syncState.noteHashes[id] { pathsToDelete.append(state.relativePath) }
                    }
                    for item in changes.changed {
                        if let state = syncState.noteHashes["\(item.id)"] { pathsToDelete.append(state.relativePath) }
                    }
                    markdownWriter.deleteFiles(relativePaths: pathsToDelete, baseURL: config.localFolderURL)

                    let writtenPaths = try markdownWriter.writeNotes(changes.changed, to: config.localFolderURL)
                    log(.notes, .incremental, "Notes — Wrote \(writtenPaths.count) files, cleaned up \(pathsToDelete.count) old files")
                    
                    for (id, path) in writtenPaths {
                        if let hash = changes.changed.first(where: { "\($0.id)" == id })?.contentHash {
                            syncState.noteHashes[id] = SyncItemState(hash: hash, relativePath: path)
                        }
                    }
                }
                
                if config.outputMode == .remote {
                    let apiClient = APIClient(config: config)
                    try await apiClient.syncNotes(changed: changes.changed, deleted: changes.deleted)
                    log(.notes, .incremental, "Notes — Pushed \(changes.changed.count) changed, \(changes.deleted.count) deleted to Remote")
                    
                    for item in changes.changed {
                        syncState.noteHashes["\(item.id)"] = SyncItemState(hash: item.contentHash, relativePath: "")
                    }
                }

                for id in changes.deleted {
                    syncState.noteHashes.removeValue(forKey: id)
                }
                syncState.save()
            } else {
                log(.notes, .info, "Notes — No changes detected")
            }

            if appState.config.outputMode == .local {
                let permitted = Set(syncState.noteHashes.values.map(\.relativePath))
                markdownWriter.purgeOrphans(permittedRelativePaths: permitted, category: "notes", baseURL: appState.config.localFolderURL)
            }

            appState.noteStatus = .synced
        } catch {
            appState.noteStatus = .error
            log(.notes, .error, "Notes — \(String(describing: error))")
        }
    }

    // MARK: - Change Detection

    private struct ChangeResult<T> {
        let changed: [T]
        let deleted: [String]
    }

    private func detectChanges<T: Identifiable & Hashable>(
        items: [T],
        existingHashes: [String: SyncItemState]
    ) -> ChangeResult<T> where T: SyncableItem {
        var changed: [T] = []
        let currentIds = Set(items.map { "\($0.id)" })
        let previousIds = Set(existingHashes.keys)

        for item in items {
            let id = "\(item.id)"
            let hash = item.contentHash
            if existingHashes[id]?.hash != hash {
                changed.append(item)
            }
        }

        let deleted = Array(previousIds.subtracting(currentIds))
        return ChangeResult(changed: changed, deleted: deleted)
    }

    // MARK: - Logging

    private func log(_ source: SyncSource, _ type: SyncEventType, _ message: String) {
        let entry = SyncLogEntry(source: source, type: type, message: message)
        appState?.addLogEntry(entry)
    }
}

// MARK: - Protocol for syncable items with contentHash

protocol SyncableItem {
    var contentHash: String { get }
}

extension SyncableContact: SyncableItem {}
extension SyncableReminder: SyncableItem {}
extension SyncableNote: SyncableItem {}
