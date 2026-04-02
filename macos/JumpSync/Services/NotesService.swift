import Foundation

/// Extracts Apple Notes using native AppleScript
class NotesService {

    /// Fetch all notes via AppleScript and keep track of unreadable/skipped items
    func fetchAllNotes() async throws -> (notes: [SyncableNote], skipped: Int) {
        // AppleScript to get all notes with their properties
        let script = """
        tell application "Notes"
            set noteList to {}
            repeat with n in every note
                set noteId to id of n
                set noteTitle to name of n
                set noteBody to body of n
                try
                    set noteFolder to name of container of n
                on error
                    set noteFolder to "Notes"
                end try
                set noteCreated to creation date of n
                set noteModified to modification date of n
                set noteRecord to noteId & "|||" & noteTitle & "|||" & noteFolder & "|||" & (noteCreated as string) & "|||" & (noteModified as string)
                set end of noteList to noteRecord
            end repeat
            set AppleScript's text item delimiters to "###"
            return noteList as string
        end tell
        """

        let output = try await runAppleScript(script)
        let records = output.components(separatedBy: "###")

        var notes: [SyncableNote] = []
        var skippedCount = 0
        for record in records {
            if record.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            
            let parts = record.components(separatedBy: "|||")
            guard parts.count >= 5 else {
                skippedCount += 1
                continue
            }

            let noteId = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let title = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let folder = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
            let created = parts[3].trimmingCharacters(in: .whitespacesAndNewlines)
            let modified = parts[4].trimmingCharacters(in: .whitespacesAndNewlines)

            // Fetch body separately — AppleScript returns HTML, we'll convert on write
            let bodyScript = """
            tell application "Notes"
                set n to first note whose id is "\(noteId)"
                return body of n
            end tell
            """
            
            let body: String
            do {
                body = try await runAppleScript(bodyScript)
            } catch {
                skippedCount += 1
                continue
            }

            let note = SyncableNote(
                id: noteId,
                title: title,
                body: stripHTML(body),
                folder: folder,
                creationDate: created,
                modificationDate: modified
            )
            notes.append(note)
        }

        return (notes, skippedCount)
    }

    // MARK: - HTML → Plain Text (basic)

    private func stripHTML(_ html: String) -> String {
        // Basic HTML tag removal — for v1
        var text = html
        // Remove common HTML tags
        let tagPattern = "<[^>]+>"
        text = text.replacingOccurrences(of: tagPattern, with: "", options: .regularExpression)
        // Decode common entities
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "<br>", with: "\n")
        text = text.replacingOccurrences(of: "<br/>", with: "\n")
        text = text.replacingOccurrences(of: "<br />", with: "\n")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - AppleScript execution

    private func runAppleScript(_ source: String) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var error: NSDictionary?
                let script = NSAppleScript(source: source)
                let result = script?.executeAndReturnError(&error)

                if let error = error {
                    let message = error[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error"
                    continuation.resume(throwing: NotesError.appleScriptFailed(message))
                } else {
                    continuation.resume(returning: result?.stringValue ?? "")
                }
            }
        }
    }
}

enum NotesError: Error, LocalizedError {
    case appleScriptFailed(String)
    case bridgeScriptMissing(String)
    case bridgeParseError(String)

    var errorDescription: String? {
        switch self {
        case .appleScriptFailed(let msg): return "AppleScript error: \(msg)"
        case .bridgeScriptMissing(let msg): return "Bridge script missing: \(msg)"
        case .bridgeParseError(let msg): return "Bridge parse error: \(msg)"
        }
    }
}
