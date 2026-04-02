import SwiftUI

/// Menu bar popup — quick status and actions
struct MenuBarView: View {
    @Environment(AppState.self) var appState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "icloud.and.arrow.up")
                    .foregroundColor(.cyan)
                Text("JumpSync")
                    .font(.headline)
                Spacer()
                statusDot
            }
            .padding(.horizontal, 14)
            .padding(.top, 4)

            Divider()

            // Quick stats
            VStack(alignment: .leading, spacing: 6) {
                if let lastSync = appState.lastSyncDate {
                    Label("Last sync: \(lastSync.relativeDescription)", systemImage: "clock")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Label("Not yet synced", systemImage: "clock")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 16) {
                    statLabel(count: appState.contactCount, label: "Contacts", icon: "person.2.fill")
                    statLabel(count: appState.reminderCount, label: "Reminders", icon: "checklist")
                    statLabel(count: appState.noteCount, label: "Notes", icon: "note.text")
                }
            }
            .padding(.horizontal, 14)

            Divider()

            // Actions
            VStack(spacing: 2) {
                MenuBarButton(
                    title: appState.isSyncing ? "Syncing..." : "Sync Now",
                    icon: "arrow.triangle.2.circlepath",
                    isDisabled: appState.isSyncing
                ) {
                    appState.triggerSync()
                    dismiss()
                }

                MenuBarButton(title: "Open Dashboard", icon: "macwindow") {
                    dismiss()
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    openWindow(id: "main")
                }
            }

            Divider()

            MenuBarButton(title: "Quit JumpSync", icon: "power", tint: .secondary) {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.vertical, 8)
        .frame(width: 280)
    }

    private var statusDot: some View {
        Circle()
            .fill(appState.isSyncing ? Color.blue : .green)
            .frame(width: 8, height: 8)
    }

    private func statLabel(count: Int, label: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text("\(count)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
        }
    }
}

// MARK: - Hoverable Menu Bar Button

struct MenuBarButton: View {
    let title: String
    let icon: String
    var tint: Color = .primary
    var isDisabled: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 16)
                    .foregroundColor(isHovered ? .white : tint)
                Text(title)
                    .font(.system(size: 13))
                    .foregroundColor(isHovered ? .white : tint)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.accentColor.opacity(0.85) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
        .padding(.horizontal, 4)
    }
}

// MARK: - Date extension

extension Date {
    var relativeDescription: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
