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

            if appState.config.outputMode == .remote {
                await reconcileRemindersRemote(local: reminders, appState: appState)
            } else {
                syncRemindersLocal(reminders, appState: appState)
            }

            appState.reminderStatus = .synced
        } catch {
            appState.reminderStatus = .error
            log(.reminders, .error, "Reminders — \(String(describing: error))")
        }
    }

    /// Local (file-only) reminder sync — unchanged one-way mirror to markdown files.
    private func syncRemindersLocal(_ reminders: [SyncableReminder], appState: AppState) {
        let config = appState.config
        let changes = detectChanges(items: reminders, existingHashes: syncState.reminderHashes)

        if !changes.changed.isEmpty || !changes.deleted.isEmpty {
            var pathsToDelete: [String] = []
            for id in changes.deleted {
                if let state = syncState.reminderHashes[id] { pathsToDelete.append(state.relativePath) }
            }
            for item in changes.changed {
                if let state = syncState.reminderHashes["\(item.id)"] { pathsToDelete.append(state.relativePath) }
            }
            markdownWriter.deleteFiles(relativePaths: pathsToDelete, baseURL: config.localFolderURL)

            let writtenPaths = (try? markdownWriter.writeReminders(changes.changed, to: config.localFolderURL)) ?? [:]
            log(.reminders, .incremental, "Reminders — Wrote \(writtenPaths.count) files, cleaned up \(pathsToDelete.count) old files")

            for (id, path) in writtenPaths {
                if let hash = changes.changed.first(where: { "\($0.id)" == id })?.contentHash {
                    syncState.reminderHashes[id] = SyncItemState(hash: hash, relativePath: path)
                }
            }
            for id in changes.deleted {
                syncState.reminderHashes.removeValue(forKey: id)
            }
            syncState.save()
        } else {
            log(.reminders, .info, "Reminders — No changes detected")
        }

        let permitted = Set(syncState.reminderHashes.values.map(\.relativePath))
        markdownWriter.purgeOrphans(permittedRelativePaths: permitted, category: "reminders", baseURL: config.localFolderURL)
    }

    /// Two-way reminder sync. Pulls the server's current state, then classifies each
    /// reminder against the last-synced baseline (`reminderHashes`) as a local-origin
    /// change (push), a server-origin change (write into EventKit), or a both-sides
    /// conflict resolved by newest-wins. Change detection is content-based (`syncHash`)
    /// so a value that has round-tripped through the server does not echo back.
    private func reconcileRemindersRemote(local: [SyncableReminder], appState: AppState) async {
        let config = appState.config
        let api = APIClient(config: config)

        let remoteItems: [APIClient.RemoteReminder]
        do {
            remoteItems = try await api.pullReminders()
        } catch APIError.serverError(let code) where code == 405 || code == 404 {
            // Server predates the two-way pull endpoint — keep syncing one-way
            // (push) so reminders aren't stuck until the server is upgraded.
            log(.reminders, .warning, "Reminders — Server has no pull endpoint (HTTP \(code)); using one-way push. Deploy the server update to enable bidirectional sync.")
            await pushRemindersOneWay(local: local, appState: appState)
            return
        } catch {
            log(.reminders, .error, "Reminders — Pull failed, skipping reconcile: \(String(describing: error))")
            return
        }

        let localById = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let remoteById = Dictionary(remoteItems.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let baseline = syncState.reminderHashes
        var newBaseline = baseline

        var pushChanged: [SyncableReminder] = []
        var pushDeleted: [String] = []
        var appliedLocal = 0
        var deletedLocal = 0
        var conflicts = 0

        // Materialize a server-origin reminder into EventKit, reconciling the
        // EventKit-assigned identifier back onto the server when it differs.
        func materialize(_ rSync: SyncableReminder, placeholderId: String) {
            do {
                let newId = try remindersService.applyUpsert(rSync)
                appliedLocal += 1
                if newId != placeholderId {
                    var reassigned = rSync
                    reassigned.id = newId
                    pushChanged.append(reassigned)
                    pushDeleted.append(placeholderId)
                    newBaseline[newId] = SyncItemState(hash: reassigned.syncHash, relativePath: "")
                    newBaseline.removeValue(forKey: placeholderId)
                } else {
                    newBaseline[placeholderId] = SyncItemState(hash: rSync.syncHash, relativePath: "")
                }
            } catch {
                log(.reminders, .error, "Reminders — Failed to write '\(rSync.title)' into Reminders: \(String(describing: error))")
            }
        }

        let allIds = Set(localById.keys).union(remoteById.keys).union(baseline.keys)

        for id in allIds {
            let base = baseline[id]?.hash

            switch (localById[id], remoteById[id]) {
            case let (l?, r?):
                let rSync = r.asSyncable
                let lChanged = l.syncHash != base
                let rChanged = rSync.syncHash != base

                if !lChanged && !rChanged {
                    newBaseline[id] = SyncItemState(hash: l.syncHash, relativePath: "")
                } else if lChanged && !rChanged {
                    pushChanged.append(l)
                    newBaseline[id] = SyncItemState(hash: l.syncHash, relativePath: "")
                } else if !lChanged && rChanged {
                    applyRemote(rSync, into: &newBaseline, applied: &appliedLocal)
                } else {
                    conflicts += 1
                    if localIsNewer(local: l, remote: r) {
                        pushChanged.append(l)
                        newBaseline[id] = SyncItemState(hash: l.syncHash, relativePath: "")
                    } else {
                        applyRemote(rSync, into: &newBaseline, applied: &appliedLocal)
                    }
                }

            case let (l?, nil):
                if base == nil || l.syncHash != base {
                    // Brand-new locally, or server deleted an item the Mac has since
                    // edited — the Mac wins; (re)push it.
                    pushChanged.append(l)
                    newBaseline[id] = SyncItemState(hash: l.syncHash, relativePath: "")
                } else {
                    // Server deleted an unchanged item — delete it locally too.
                    do {
                        try remindersService.applyDelete(id: id)
                        deletedLocal += 1
                    } catch {
                        log(.reminders, .error, "Reminders — Failed to delete local '\(l.title)': \(String(describing: error))")
                    }
                    newBaseline.removeValue(forKey: id)
                }

            case let (nil, r?):
                let rSync = r.asSyncable
                if base == nil || rSync.syncHash != base {
                    // Brand-new on the server, or the Mac deleted an item the server has
                    // since edited — the server wins; materialize it into EventKit.
                    materialize(rSync, placeholderId: id)
                } else {
                    // Mac deleted an unchanged item — remove it on the server too.
                    pushDeleted.append(id)
                    newBaseline.removeValue(forKey: id)
                }

            case (nil, nil):
                newBaseline.removeValue(forKey: id)
            }
        }

        if !pushChanged.isEmpty || !pushDeleted.isEmpty {
            do {
                try await api.syncReminders(changed: pushChanged, deleted: pushDeleted)
            } catch {
                log(.reminders, .error, "Reminders — Push failed: \(String(describing: error))")
            }
        }

        syncState.reminderHashes = newBaseline
        syncState.save()

        log(.reminders, .incremental,
            "Reminders — Reconciled: ↑\(pushChanged.count) pushed, ↓\(appliedLocal) applied, \(deletedLocal) deleted locally, \(pushDeleted.count) removed on server, \(conflicts) conflicts")
    }

    /// Legacy one-way push, used when the server lacks the two-way pull endpoint.
    /// Uses `syncHash` for the baseline so no spurious diff appears once the server
    /// is upgraded and reconcile takes over.
    private func pushRemindersOneWay(local: [SyncableReminder], appState: AppState) async {
        let api = APIClient(config: appState.config)
        let baseline = syncState.reminderHashes

        let changed = local.filter { $0.syncHash != baseline[$0.id]?.hash }
        let currentIds = Set(local.map { $0.id })
        let deleted = baseline.keys.filter { !currentIds.contains($0) }

        guard !changed.isEmpty || !deleted.isEmpty else {
            log(.reminders, .info, "Reminders — No changes detected (one-way push)")
            return
        }

        do {
            try await api.syncReminders(changed: changed, deleted: Array(deleted))
            for r in changed {
                syncState.reminderHashes[r.id] = SyncItemState(hash: r.syncHash, relativePath: "")
            }
            for id in deleted {
                syncState.reminderHashes.removeValue(forKey: id)
            }
            syncState.save()
            log(.reminders, .incremental, "Reminders — One-way push: ↑\(changed.count) pushed, \(deleted.count) deleted on server")
        } catch {
            log(.reminders, .error, "Reminders — One-way push failed: \(String(describing: error))")
        }
    }

    private func applyRemote(_ rSync: SyncableReminder, into baseline: inout [String: SyncItemState], applied: inout Int) {
        do {
            let newId = try remindersService.applyUpsert(rSync)
            applied += 1
            baseline[newId] = SyncItemState(hash: rSync.syncHash, relativePath: "")
            if newId != rSync.id {
                baseline.removeValue(forKey: rSync.id)
            }
        } catch {
            log(.reminders, .error, "Reminders — Failed to apply remote edit '\(rSync.title)': \(String(describing: error))")
        }
    }

    private func localIsNewer(local: SyncableReminder, remote: APIClient.RemoteReminder) -> Bool {
        let l = local.modificationDate.flatMap(Self.parseTimestamp)
        let r = remote.serverModified.flatMap(Self.parseTimestamp)
        switch (l, r) {
        case let (l?, r?): return l >= r
        case (_?, nil): return true
        case (nil, _?): return false
        case (nil, nil): return true
        }
    }

    private static func parseTimestamp(_ s: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: s)
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
