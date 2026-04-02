import Foundation
import AppKit

/// Uses the local python bridge (apple-notes-parser) to parse SQLite NoteStore directly.
/// This implementation allows harvesting tags and multimodal metadata.
class SQLiteNotesService {

    private func checkAndRequestPermissions() async throws {
        let notesDir = NSHomeDirectory() + "/Library/Group Containers/group.com.apple.notes"
        let dbPath = notesDir + "/NoteStore.sqlite"
        
        if FileManager.default.isReadableFile(atPath: dbPath) {
            return
        }
        
        let granted = await MainActor.run { () -> Bool in
            let alert = NSAlert()
            alert.messageText = "Apple Notes Access Required"
            alert.informativeText = "JumpSync needs access to your Apple Notes folder. Please select 'Open' in the following Finder window to grant read permission."
            alert.addButton(withTitle: "Continue")
            alert.runModal()
            
            let panel = NSOpenPanel()
            panel.message = "Grant JumpSync Access to Apple Notes"
            panel.directoryURL = URL(fileURLWithPath: notesDir)
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            
            return panel.runModal() == .OK
        }
        
        if !granted {
            throw NotesError.bridgeParseError("User canceled folder permission request.")
        }
        
        // Minor delay to let macOS propagate the temporary security exception
        try? await Task.sleep(nanoseconds: 500_000_000)
    }

    /// Fetch all notes via the python bridge script
    func fetchAllNotes(scriptURL: URL, progress: @escaping (String) -> Void) async throws -> (notes: [SyncableNote], skipped: Int) {
        try await checkAndRequestPermissions()
        
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            throw NotesError.bridgeScriptMissing("Could not find \(scriptURL.lastPathComponent)")
        }

        let outputStr = try await runProcess(path: "/bin/sh", args: [scriptURL.path], progress: progress)
        guard let jsonData = outputStr.data(using: .utf8),
              let bridgeResult = try? JSONDecoder().decode(NotesExporterResult.self, from: jsonData) else {
            throw NotesError.bridgeParseError("Failed to parse bridge output.")
        }

        let exportFileURL = URL(fileURLWithPath: bridgeResult.exportFile)
        guard FileManager.default.fileExists(atPath: exportFileURL.path) else {
            throw NotesError.bridgeParseError("Export JSON file not generated. Did you grant Full Disk Access to Notes?")
        }

        let exportedData = try Data(contentsOf: exportFileURL)
        let exportWrapper = try JSONDecoder().decode(RawAppleNotesExport.self, from: exportedData)
        let rawNotes = exportWrapper.notes

        let mediaDir = URL(fileURLWithPath: bridgeResult.mediaDir)
        
        var notes: [SyncableNote] = []
        var skippedCount = 0

        for raw in rawNotes {
            if raw.is_password_protected {
                skippedCount += 1
                continue
            }

            var parsedAttachments: [SyncableAttachment] = []
            if let atts = raw.attachments {
                for att in atts {
                    // Try to construct standard path and read Base64
                    // apple-notes-parser attachments CLI saves files by their UUID or name. 
                    // Typically it saves them as {uuid}.ext or similar. We should read the mediaDir to find it.
                    // For safety, we match the filename or UUID.
                    let safeFilename = att.filename ?? "Attachment_\(att.uuid)"
                    let potentialURL = mediaDir.appendingPathComponent("\(att.uuid).\(att.file_extension ?? "bin")")
                    var b64 = ""
                    if FileManager.default.fileExists(atPath: potentialURL.path) {
                        if let fileData = try? Data(contentsOf: potentialURL) {
                            b64 = fileData.base64EncodedString()
                        }
                    } else {
                        // fallback to filename
                        let fallback = mediaDir.appendingPathComponent(safeFilename)
                        if let fileData = try? Data(contentsOf: fallback) {
                            b64 = fileData.base64EncodedString()
                        }
                    }
                    
                    if b64.isEmpty {
                        continue
                    }
                    
                    parsedAttachments.append(SyncableAttachment(
                        id: att.uuid,
                        filename: safeFilename,
                        mimeType: att.mime_type ?? "application/octet-stream",
                        base64Data: b64
                    ))
                }
            }

            let note = SyncableNote(
                id: raw.uuid,
                title: raw.title ?? "Untitled",
                body: raw.content ?? "",
                folder: raw.folder_path ?? "Notes",
                tags: raw.tags,
                attachments: parsedAttachments.isEmpty ? nil : parsedAttachments,
                creationDate: raw.creation_date,
                modificationDate: raw.modification_date
            )
            notes.append(note)
        }

        return (notes, skippedCount)
    }

    // MARK: - Process Execution
    
    private func runProcess(path: String, args: [String], progress: @escaping (String) -> Void) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: path)
                task.arguments = args
                
                let pipe = Pipe()
                task.standardOutput = pipe
                let errorPipe = Pipe()
                task.standardError = errorPipe
                
                var stdoutData = Data()
                var stderrData = Data()
                let dataQueue = DispatchQueue(label: "com.jumpsync.pipedata")
                
                let group = DispatchGroup()
                
                group.enter()
                pipe.fileHandleForReading.readabilityHandler = { fh in
                    let data = fh.availableData
                    if data.isEmpty {
                        pipe.fileHandleForReading.readabilityHandler = nil
                        group.leave()
                    } else {
                        dataQueue.async { stdoutData.append(data) }
                    }
                }
                
                group.enter()
                errorPipe.fileHandleForReading.readabilityHandler = { fh in
                    let data = fh.availableData
                    if data.isEmpty {
                        errorPipe.fileHandleForReading.readabilityHandler = nil
                        group.leave()
                    } else {
                        dataQueue.async { stderrData.append(data) }
                        if let line = String(data: data, encoding: .utf8) {
                            progress(line.trimmingCharacters(in: .whitespacesAndNewlines))
                        }
                    }
                }
                
                do {
                    try task.run()
                    task.waitUntilExit()
                    group.wait()
                    
                    if task.terminationStatus != 0 {
                        let errStr = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown Error"
                        continuation.resume(throwing: NotesError.bridgeParseError("Script failed with status \(task.terminationStatus): \(errStr)"))
                    } else if let output = String(data: stdoutData, encoding: .utf8) {
                        continuation.resume(returning: output)
                    } else {
                        continuation.resume(throwing: NotesError.bridgeParseError("Invalid text output format"))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

// MARK: - Bridge Data Models

fileprivate struct NotesExporterResult: Codable {
    let exportFile: String
    let mediaDir: String
}

fileprivate struct RawFolder: Codable {
    let name: String
}

fileprivate struct RawAttachment: Codable {
    let uuid: String
    let filename: String?
    let mime_type: String?
    let file_extension: String?
}

fileprivate struct RawAppleNote: Codable {
    let uuid: String
    let title: String?
    let content: String?
    let creation_date: String?
    let modification_date: String?
    let is_password_protected: Bool
    let folder_name: String?
    let folder_path: String?
    let tags: [String]?
    let attachments: [RawAttachment]?
}

fileprivate struct RawAppleNotesExport: Codable {
    let notes: [RawAppleNote]
}
