import Foundation

/// Generic wrapper for running CLI tools (remindctl, memo) via Process
actor CLIRunner {
    enum CLIError: Error, LocalizedError {
        case notInstalled(String)
        case executionFailed(String, Int32)
        case timeout

        var errorDescription: String? {
            switch self {
            case .notInstalled(let tool): return "\(tool) is not installed. Check Configuration for install instructions."
            case .executionFailed(let output, let code): return "Command failed (exit \(code)): \(output)"
            case .timeout: return "Command timed out"
            }
        }
    }

    /// Check if a CLI tool is available
    static func isInstalled(_ tool: String) -> Bool {
        let process = Process()
        process.launchPath = "/usr/bin/which"
        process.arguments = [tool]
        
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        process.environment = env
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Run a CLI tool and capture stdout
    func run(tool: String, arguments: [String], timeout: TimeInterval = 30) async throws -> String {
        // Verify tool is available
        guard CLIRunner.isInstalled(tool) else {
            throw CLIError.notInstalled(tool)
        }

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.launchPath = "/usr/bin/env"
            process.arguments = [tool] + arguments

            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
            process.environment = env

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            process.terminationHandler = { proc in
                let outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: outputData, encoding: .utf8) ?? ""
                let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

                if proc.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(throwing: CLIError.executionFailed(
                        errorOutput.isEmpty ? output : errorOutput,
                        proc.terminationStatus
                    ))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }

            // Timeout
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if process.isRunning {
                    process.terminate()
                }
            }
        }
    }
}
