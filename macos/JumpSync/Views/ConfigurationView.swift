import SwiftUI

/// Configuration page — global settings and per-source toggles
struct ConfigurationView: View {
    @Environment(AppState.self) var appState
    @State private var isAPIKeyVisible: Bool = false

    // Cache CLI installation status to avoid running Process during view body
    var body: some View {
        @Bindable var appState = appState

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // 1. General Settings
                generalSettingsSection(appState: $appState)

                // 2. Local Settings (shown when mode is local)
                if appState.config.outputMode == .local {
                    localSettingsSection(appState: $appState)
                }

                // 3. Remote Settings (shown when mode is remote)
                if appState.config.outputMode == .remote {
                    remoteSettingsSection(appState: $appState)
                }

                // 4. Data Sources
                dataSourcesSection(appState: $appState)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - General Settings

    private func generalSettingsSection(appState: Bindable<AppState>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("General Settings")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.secondary)

            VStack(spacing: 0) {
                // Output Mode
                settingRow(label: "Output Mode") {
                    Picker("", selection: appState.config.outputMode) {
                        ForEach(OutputMode.allCases, id: \.self)    { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }

                Divider().padding(.leading, 16)

                // Sync Interval
                settingRow(label: "Sync Interval") {
                    Picker("", selection: appState.config.syncIntervalMinutes) {
                        Text("Every 15 minutes").tag(15)
                        Text("Every 30 minutes").tag(30)
                        Text("Every hour").tag(60)
                        Text("Manual only").tag(0)
                    }
                    .frame(width: 180)
                }

                Divider().padding(.leading, 16)

                // Auto-start
                settingRow(label: "Auto-start on login") {
                    Toggle("", isOn: appState.config.autoStartOnLogin)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
        }
        .onChange(of: self.appState.config.outputMode) { _, _ in self.appState.config.save() }
        .onChange(of: self.appState.config.syncIntervalMinutes) { _, _ in self.appState.config.save() }
        .onChange(of: self.appState.config.autoStartOnLogin) { _, _ in self.appState.config.save() }
    }

    // MARK: - Local Settings

    private func localSettingsSection(appState: Bindable<AppState>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Local Backup")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.secondary)

            VStack(spacing: 0) {
                settingRow(label: "Local Folder") {
                    HStack(spacing: 8) {
                        Text(compactPath(self.appState.config.localFolderPath))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Button("Browse…") {
                            pickFolder()
                        }
                        .controlSize(.small)
                    }
                }
            }
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
        }
    }

    // MARK: - Remote Settings

    private func remoteSettingsSection(appState: Bindable<AppState>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Remote Server")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.secondary)

            VStack(spacing: 0) {
                settingRow(label: "Server URL") {
                    TextField("https://your-server.com", text: appState.config.serverURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 260)
                        .onSubmit { self.appState.config.save() }
                }

                Divider().padding(.leading, 16)

                settingRow(label: "API Key") {
                    HStack(spacing: 8) {
                        if isAPIKeyVisible {
                            TextField("Enter API key", text: appState.config.apiKey)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { self.appState.config.save() }
                        } else {
                            SecureField("Enter API key", text: appState.config.apiKey)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { self.appState.config.save() }
                        }
                        
                        Button {
                            isAPIKeyVisible.toggle()
                        } label: {
                            Image(systemName: isAPIKeyVisible ? "eye.slash.fill" : "eye.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(width: 260)
                }
            }
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
        }
        .onChange(of: self.appState.config.serverURL) { _, _ in self.appState.config.save() }
        .onChange(of: self.appState.config.apiKey) { _, _ in self.appState.config.save() }
    }

    // MARK: - Data Sources

    private func dataSourcesSection(appState: Bindable<AppState>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Data Sources")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.secondary)

            VStack(spacing: 0) {
                DataSourceCard(
                    name: "Contacts",
                    icon: "person.2.fill",
                    provider: "CNContactStore",
                    itemCount: self.appState.contactCount,
                    isEnabled: appState.config.contactsEnabled,
                    status: self.appState.contactStatus,
                    installNote: nil
                )

                
                Divider().padding(.leading, 16)

                DataSourceCard(
                    name: "Reminders",
                    icon: "checklist",
                    provider: "EventKit",
                    itemCount: self.appState.reminderCount,
                    isEnabled: appState.config.remindersEnabled,
                    status: self.appState.reminderStatus,
                    installNote: nil
                )
                
                Divider().padding(.leading, 16)

                DataSourceCard(
                    name: "Notes",
                    icon: "note.text",
                    provider: "AppleScript",
                    itemCount: self.appState.noteCount,
                    isEnabled: appState.config.notesEnabled,
                    status: self.appState.noteStatus,
                    installNote: nil
                )
            }
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
        }
        .onChange(of: self.appState.config.contactsEnabled) { _, _ in self.appState.config.save() }
        .onChange(of: self.appState.config.remindersEnabled) { _, _ in self.appState.config.save() }
        .onChange(of: self.appState.config.notesEnabled) { _, _ in self.appState.config.save() }
    }

    // MARK: - Helpers

    private func settingRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
            Spacer()
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Sync Folder"
        if panel.runModal() == .OK, let url = panel.url {
            appState.config.localFolderPath = url.path
            appState.config.save()
        }
    }

    private func compactPath(_ path: String) -> String {
        path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
    }
}

// MARK: - Data Source Card

struct DataSourceCard: View {
    let name: String
    let icon: String
    let provider: String
    let itemCount: Int
    @Binding var isEnabled: Bool
    let status: SourceStatus
    let installNote: String?

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(status.color)
                .frame(width: 8, height: 8)

            Image(systemName: icon)
                .frame(width: 20)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 13, weight: .medium))
                HStack(spacing: 4) {
                    Text(provider)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text("•")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text("\(itemCount) items")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    if let note = installNote {
                        Text("•")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Text("Install: \(note)")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            Toggle("", isOn: $isEnabled)
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

#Preview {
    ConfigurationView()
        .environment(AppState())
        .frame(width: 600, height: 500)
}
