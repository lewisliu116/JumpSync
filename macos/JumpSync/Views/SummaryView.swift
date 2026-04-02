import SwiftUI

/// Summary / Home page — sync stats, status per source, recent activity
struct SummaryView: View {
    @Environment(AppState.self) var appState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Sync Status
                syncStatusSection

                // Recent Activity
                recentActivitySection
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Sync Status

    private var syncStatusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sync Status")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.secondary)

            VStack(spacing: 0) {
                SourceStatusRow(
                    name: "Contacts",
                    icon: "person.2.fill",
                    status: appState.contactStatus,
                    count: appState.contactCount,
                    provider: "CNContactStore"
                )
                Divider().padding(.leading, 36)
                SourceStatusRow(
                    name: "Reminders",
                    icon: "checklist",
                    status: appState.reminderStatus,
                    count: appState.reminderCount,
                    provider: "EventKit"
                )
                Divider().padding(.leading, 36)
                SourceStatusRow(
                    name: "Notes",
                    icon: "note.text",
                    status: appState.noteStatus,
                    count: appState.noteCount,
                    provider: "AppleScript"
                )
            }
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
        }
    }

    // MARK: - Recent Activity

    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent Activity")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.secondary)
                Spacer()
                Button("View All") {
                    appState.selectedTab = .history
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundColor(.cyan)
            }

            if appState.syncHistory.isEmpty {
                Text("No sync activity yet. Click 'Sync Now' to get started.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(appState.syncHistory.prefix(5)) { entry in
                        LogEntryRow(entry: entry, compact: true)
                        if entry.id != appState.syncHistory.prefix(5).last?.id {
                            Divider().padding(.leading, 12)
                        }
                    }
                }
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
            }
        }
    }
}

// MARK: - Source Status Row

struct SourceStatusRow: View {
    let name: String
    let icon: String
    let status: SourceStatus
    let count: Int
    let provider: String

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(status.color)
                .frame(width: 8, height: 8)

            Image(systemName: icon)
                .frame(width: 20)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 13, weight: .medium))
                Text("via \(provider)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text("\(count) synced")
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Log Entry Row

struct LogEntryRow: View {
    let entry: SyncLogEntry
    var compact: Bool = false

    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = compact ? "HH:mm" : "HH:mm:ss"
        return f
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(timeFormatter.string(from: entry.timestamp))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: compact ? 40 : 60, alignment: .trailing)

            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)

            Text(entry.message)
                .font(.system(size: 12))
                .lineLimit(compact ? 1 : 3)
                .textSelection(.enabled)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var dotColor: Color {
        switch entry.type {
        case .fullSync: return .blue
        case .incremental: return .green
        case .error: return .red
        case .warning: return .yellow
        case .info: return .gray
        }
    }
}

#Preview {
    SummaryView()
        .environment(AppState())
        .frame(width: 600, height: 500)
}
