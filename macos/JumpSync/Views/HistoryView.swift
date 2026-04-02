import SwiftUI

/// History / Logs page — filterable sync log
struct HistoryView: View {
    @Environment(AppState.self) var appState
    @State private var selectedFilter: SyncSourceFilter = .all
    @State private var searchText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Filter bar
            HStack(spacing: 12) {
                Picker("", selection: $selectedFilter) {
                    ForEach(SyncSourceFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 340)

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    TextField("Search logs…", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .frame(width: 150)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
            }
            .padding(.horizontal, 24)

            // Log entries
            if filteredEntries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("No log entries")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    Text("Sync activity will appear here.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredEntries) { entry in
                            LogEntryRow(entry: entry, compact: false)
                            Divider().padding(.leading, 72)
                        }
                    }
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 24)
                }
            }

            // Footer
            HStack {
                Text("\(filteredEntries.count) entries")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var filteredEntries: [SyncLogEntry] {
        appState.syncHistory.filter { entry in
            let matchesFilter: Bool
            switch selectedFilter {
            case .all: matchesFilter = true
            case .contacts: matchesFilter = entry.source == .contacts
            case .reminders: matchesFilter = entry.source == .reminders
            case .notes: matchesFilter = entry.source == .notes
            }

            let matchesSearch = searchText.isEmpty ||
                entry.message.localizedCaseInsensitiveContains(searchText)

            return matchesFilter && matchesSearch
        }
    }
}

enum SyncSourceFilter: String, CaseIterable {
    case all = "All"
    case contacts = "Contacts"
    case reminders = "Reminders"
    case notes = "Notes"
}

#Preview {
    let state = AppState()
    state.syncHistory = [
        SyncLogEntry(source: .contacts, type: .incremental, message: "Contacts — Incremental sync: 3 updated, 0 deleted"),
        SyncLogEntry(source: .reminders, type: .incremental, message: "Reminders — 1 new reminder added"),
        SyncLogEntry(source: .system, type: .fullSync, message: "Full Sync — 342 contacts, 28 reminders, 156 notes"),
        SyncLogEntry(source: .notes, type: .incremental, message: "Notes — 2 notes modified"),
        SyncLogEntry(source: .reminders, type: .error, message: "Reminders — Error: remindctl not found"),
    ]
    return HistoryView()
        .environment(state)
        .frame(width: 600, height: 500)
}
