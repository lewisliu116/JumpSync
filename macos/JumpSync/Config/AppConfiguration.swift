import Foundation

enum OutputMode: String, Codable, CaseIterable {
    case local = "Local Only"
    case remote = "Remote Server"
}

/// User-facing app configuration backed by UserDefaults
struct AppConfiguration: Codable {
    var outputMode: OutputMode = .local
    var localFolderPath: String = defaultLocalFolder()
    var serverURL: String = ""
    var apiKey: String = ""
    var syncIntervalMinutes: Int = 15
    var autoStartOnLogin: Bool = false

    var contactsEnabled: Bool = true
    var remindersEnabled: Bool = true
    var notesEnabled: Bool = true

    // MARK: - Persistence

    private static let key = "JumpSyncConfig"

    static func load() -> AppConfiguration {
        guard let data = UserDefaults.standard.data(forKey: key),
              var config = try? JSONDecoder().decode(AppConfiguration.self, from: data) else {
            return AppConfiguration()
        }
        
        let oldDefault = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("JumpSync").path
        if config.localFolderPath == oldDefault {
            config.localFolderPath = defaultLocalFolder()
            config.save()
        }
        
        return config
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: AppConfiguration.key)
    }

    var localFolderURL: URL {
        URL(fileURLWithPath: localFolderPath)
    }

    static func defaultLocalFolder() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Documents").appendingPathComponent("JumpSync").path
    }
}
