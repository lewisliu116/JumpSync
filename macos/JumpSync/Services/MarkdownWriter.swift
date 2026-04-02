import Foundation

/// Writes syncable models to markdown files with YAML frontmatter
class MarkdownWriter {
    private let fileManager = FileManager.default

    /// Write all contacts to the output folder and return ID -> relativePath mapping
    func writeContacts(_ contacts: [SyncableContact], to baseURL: URL) throws -> [String: String] {
        let dir = baseURL.appendingPathComponent("contacts", isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)

        var writtenPaths: [String: String] = [:]
        for contact in contacts {
            let displayName = contact.fullName.isEmpty ? 
                (contact.organizationName.isEmpty ? "unnamed" : contact.organizationName) : 
                contact.fullName
            let safeName = sanitizeFilename(displayName)
            let shortId = generateShortId(contact.id)
            let filename = "\(safeName)-\(shortId).md"
            
            let fileURL = dir.appendingPathComponent(filename)
            let content = renderContact(contact)
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            writtenPaths[contact.id] = "contacts/\(filename)"
        }
        return writtenPaths
    }

    /// Write all reminders to the output folder and return ID -> relativePath mapping
    func writeReminders(_ reminders: [SyncableReminder], to baseURL: URL) throws -> [String: String] {
        let dir = baseURL.appendingPathComponent("reminders", isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)

        var writtenPaths: [String: String] = [:]
        let grouped = Dictionary(grouping: reminders, by: \.list)
        for (list, items) in grouped {
            let listFolder = sanitizeFilename(list.lowercased())
            let listDir = dir.appendingPathComponent(listFolder, isDirectory: true)
            try fileManager.createDirectory(at: listDir, withIntermediateDirectories: true)

            for reminder in items {
                let safeName = sanitizeFilename(reminder.title.isEmpty ? "untitled" : reminder.title)
                let shortId = generateShortId(reminder.id)
                let filename = "\(safeName)-\(shortId).md"
                
                let fileURL = listDir.appendingPathComponent(filename)
                let content = renderReminder(reminder)
                try content.write(to: fileURL, atomically: true, encoding: .utf8)
                writtenPaths[reminder.id] = "reminders/\(listFolder)/\(filename)"
            }
        }
        return writtenPaths
    }

    /// Write all notes to the output folder and return ID -> relativePath mapping
    func writeNotes(_ notes: [SyncableNote], to baseURL: URL) throws -> [String: String] {
        let dir = baseURL.appendingPathComponent("notes", isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)

        let mediaDir = dir.appendingPathComponent("media", isDirectory: true)
        if !fileManager.fileExists(atPath: mediaDir.path) {
            try? fileManager.createDirectory(at: mediaDir, withIntermediateDirectories: true)
        }

        var writtenPaths: [String: String] = [:]
        let grouped = Dictionary(grouping: notes, by: \.folder)
        for (folder, items) in grouped {
            let folderDir: URL
            let folderName = sanitizePath(folder.lowercased())
            if folder.isEmpty || folder == "Notes" {
                folderDir = dir
            } else {
                folderDir = dir.appendingPathComponent(folderName, isDirectory: true)
                try fileManager.createDirectory(at: folderDir, withIntermediateDirectories: true)
            }

            for note in items {
                let safeName = sanitizeFilename(note.title.isEmpty ? "untitled" : note.title)
                let shortId = generateShortId(note.id)
                let filename = "\(safeName)-\(shortId).md"
                
                let fileURL = folderDir.appendingPathComponent(filename)
                let content = renderNote(note)
                try content.write(to: fileURL, atomically: true, encoding: .utf8)
                
                if let atts = note.attachments {
                    for att in atts {
                        if let data = Data(base64Encoded: att.base64Data) {
                            let ext = att.filename.components(separatedBy: ".").last ?? "bin"
                            let attURL = mediaDir.appendingPathComponent("\(att.id).\(ext)")
                            try? data.write(to: attURL)
                        }
                    }
                }
                
                let relativePrefix = (folder.isEmpty || folder == "Notes") ? "notes" : "notes/\(folderName)"
                writtenPaths[note.id] = "\(relativePrefix)/\(filename)"
            }
        }
        return writtenPaths
    }

    /// Recursively scans a category directory and deletes any `.md` file not in the permitted relative paths
    func purgeOrphans(permittedRelativePaths: Set<String>, category: String, baseURL: URL) {
        let dir = baseURL.appendingPathComponent(category, isDirectory: true)
        guard fileManager.fileExists(atPath: dir.path) else { return }

        guard let enumerator = fileManager.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey]) else { return }

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "md" else { continue }
            
            let pathComponents = fileURL.pathComponents
            let baseComponents = baseURL.pathComponents
            let relativeComponentArray = pathComponents.dropFirst(baseComponents.count)
            let relativePath = relativeComponentArray.joined(separator: "/")

            if !permittedRelativePaths.contains(relativePath) {
                try? fileManager.removeItem(at: fileURL)
            }
        }
    }

    /// Deletes specific relative paths from the base folder
    func deleteFiles(relativePaths: [String], baseURL: URL) {
        for path in relativePaths {
            guard !path.isEmpty else { continue }
            let fileURL = baseURL.appendingPathComponent(path)
            try? fileManager.removeItem(at: fileURL)
        }
    }

    // MARK: - Markdown Rendering

    private func renderContact(_ c: SyncableContact) -> String {
        var frontmatter: [String] = [
            "---",
            "id: \"\(c.id)\"",
            "type: contact",
            "source: apple_contacts",
            "name: \"\(c.fullName)\"",
        ]

        if !c.emailAddresses.isEmpty {
            frontmatter.append("email: [\(c.emailAddresses.map { "\"\($0.value)\"" }.joined(separator: ", "))]")
        }
        if !c.phoneNumbers.isEmpty {
            frontmatter.append("phone: [\(c.phoneNumbers.map { "\"\($0.value)\"" }.joined(separator: ", "))]")
        }
        if !c.organizationName.isEmpty {
            frontmatter.append("company: \"\(c.organizationName)\"")
        }
        if !c.jobTitle.isEmpty {
            frontmatter.append("job_title: \"\(c.jobTitle)\"")
        }
        if let birthday = c.birthday {
            frontmatter.append("birthday: \"\(birthday)\"")
        }
        frontmatter.append("synced_at: \"\(ISO8601DateFormatter().string(from: Date()))\"")
        frontmatter.append("---")

        var body = "\n# \(c.fullName)\n"

        if !c.organizationName.isEmpty {
            body += "\n**Company:** \(c.organizationName)"
            if !c.jobTitle.isEmpty { body += " — \(c.jobTitle)" }
            body += "\n"
        }

        if !c.emailAddresses.isEmpty {
            body += "\n## Email\n"
            for email in c.emailAddresses {
                body += "- **\(email.label):** \(email.value)\n"
            }
        }

        if !c.phoneNumbers.isEmpty {
            body += "\n## Phone\n"
            for phone in c.phoneNumbers {
                body += "- **\(phone.label):** \(phone.value)\n"
            }
        }

        if !c.postalAddresses.isEmpty {
            body += "\n## Addresses\n"
            for addr in c.postalAddresses {
                body += "- **\(addr.label):** \(addr.formatted)\n"
            }
        }

        if !c.socialProfiles.isEmpty {
            body += "\n## Social\n"
            for profile in c.socialProfiles {
                body += "- **\(profile.label):** \(profile.value)\n"
            }
        }

        if !c.urlAddresses.isEmpty {
            body += "\n## URLs\n"
            for url in c.urlAddresses {
                body += "- \(url.value)\n"
            }
        }

        if let note = c.note, !note.isEmpty {
            body += "\n## Notes\n\(note)\n"
        }

        return frontmatter.joined(separator: "\n") + body
    }

    private func renderReminder(_ r: SyncableReminder) -> String {
        var frontmatter: [String] = [
            "---",
            "id: \"\(r.id)\"",
            "type: reminder",
            "source: apple_reminders",
            "title: \"\(r.title)\"",
            "list: \"\(r.list)\"",
            "priority: \(r.priority)",
            "completed: \(r.isCompleted)",
        ]
        if let due = r.dueDate { frontmatter.append("due_date: \"\(due)\"") }
        if let notes = r.notes, !notes.isEmpty { frontmatter.append("notes: \"\(notes.replacingOccurrences(of: "\"", with: "\\\""))\"") }
        frontmatter.append("synced_at: \"\(ISO8601DateFormatter().string(from: Date()))\"")
        frontmatter.append("---")

        var body = "\n# \(r.title)\n"
        body += "\n- **List:** \(r.list)\n"
        body += "- **Priority:** \(r.priority == 0 ? "None" : "\(r.priority)")\n"
        body += "- **Status:** \(r.isCompleted ? "✅ Completed" : "⬜ Pending")\n"
        if let due = r.dueDate { body += "- **Due:** \(due)\n" }
        if let notes = r.notes, !notes.isEmpty { body += "\n## Notes\n\(notes)\n" }

        return frontmatter.joined(separator: "\n") + body
    }

    private func renderNote(_ n: SyncableNote) -> String {
        var frontmatter: [String] = [
            "---",
            "id: \"\(n.id)\"",
            "type: note",
            "source: apple_notes",
            "title: \"\(n.title.replacingOccurrences(of: "\"", with: "\\\""))\"",
            "folder: \"\(n.folder)\"",
        ]
        if let created = n.creationDate { frontmatter.append("created_at: \"\(created)\"") }
        if let modified = n.modificationDate { frontmatter.append("modified_at: \"\(modified)\"") }
        if let tags = n.tags, !tags.isEmpty {
            let tagsStr = tags.map { "\"\($0)\"" }.joined(separator: ", ")
            frontmatter.append("tags: [\(tagsStr)]")
        }
        frontmatter.append("synced_at: \"\(ISO8601DateFormatter().string(from: Date()))\"")
        frontmatter.append("---")

        var body = "\n# \(n.title)\n\n"
        var noteBody = n.body
        
        if let atts = n.attachments, !atts.isEmpty {
            noteBody += "\n\n## Internal Attachments\n"
            for att in atts {
                let ext = att.filename.components(separatedBy: ".").last ?? "bin"
                let depth = String(n.folder).components(separatedBy: "/").count
                let upPath = String(repeating: "../", count: depth)
                let relPath = (n.folder.isEmpty || n.folder == "Notes") ? "media/\(att.id).\(ext)" : "\(upPath)media/\(att.id).\(ext)"
                if att.mimeType.starts(with: "image/") {
                    noteBody += "![img](\(relPath))\n"
                } else {
                    noteBody += "[\(att.filename)](\(relPath))\n"
                }
            }
        }
        body += noteBody + "\n"

        return frontmatter.joined(separator: "\n") + body
    }

    // MARK: - Helpers

    private func sanitizeFilename(_ name: String) -> String {
        var sanitized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // Keep anything that is a unicode letter (\p{L}), mark (\p{M}), or number (\p{N}), plus hyphens and underscores
        sanitized = sanitized.replacingOccurrences(of: "[^\\p{L}\\p{M}\\p{N}\\s_-]", with: "", options: .regularExpression)
        // Replace spaces with hyphens
        sanitized = sanitized.replacingOccurrences(of: "\\s+", with: "-", options: .regularExpression)
        if sanitized.isEmpty { sanitized = "untitled" }
        return String(sanitized.prefix(80))
    }

    private func sanitizePath(_ path: String) -> String {
        return path.components(separatedBy: "/").map { sanitizeFilename($0) }.joined(separator: "/")
    }

    private func generateShortId(_ id: String) -> String {
        // Apple Notes returns 'x-coredata://[UUID]/ICNote/p234'
        if id.starts(with: "x-coredata") || id.contains("/") {
            if let lastComponent = id.components(separatedBy: "/").last, !lastComponent.isEmpty {
                return String(lastComponent.prefix(8))
            }
        }
        
        // Contacts/Reminders use raw UUIDs. Prefix is safe.
        let clean = id.replacingOccurrences(of: "[^a-zA-Z0-9]", with: "", options: .regularExpression)
        return String(clean.prefix(6))
    }
}
