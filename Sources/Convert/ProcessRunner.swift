import Foundation

enum ConvertError: LocalizedError {
    case ffmpegMissing
    case toolFailed(String)
    case unreadable(String)
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .ffmpegMissing:
            return "ffmpeg isn't installed. Run `brew install ffmpeg` in Terminal, then try again."
        case .toolFailed(let detail): return detail
        case .unreadable(let name): return "Couldn't read \(name)."
        case .unsupported(let detail): return detail
        }
    }
}

/// Finds command-line tools. GUI apps don't inherit the shell PATH, so we check the usual
/// Homebrew prefixes first and fall back to asking a login shell.
enum ToolLocator {
    private static var cache: [String: URL] = [:]
    private static let lock = NSLock()

    static func find(_ name: String) -> URL? {
        lock.lock(); defer { lock.unlock() }
        if let hit = cache[name] { return hit }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "\(home)/.homebrew/bin/\(name)",
            "\(home)/homebrew/bin/\(name)",
            "/opt/local/bin/\(name)",
            "/usr/bin/\(name)",
        ]
        if let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            let url = URL(fileURLWithPath: path)
            cache[name] = url
            return url
        }
        if let path = loginShellLookup(name) {
            let url = URL(fileURLWithPath: path)
            cache[name] = url
            return url
        }
        return nil
    }

    private static func loginShellLookup(_ name: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", "command -v \(name)"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        p.waitUntilExit()
        let s = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (p.terminationStatus == 0 && s.hasPrefix("/")) ? s : nil
    }
}

/// Runs a subprocess asynchronously, streams stdout lines, keeps a stderr tail for error
/// messages, and terminates the process if the surrounding Task is cancelled.
enum ProcessRunner {
    @discardableResult
    static func run(_ executable: URL,
                    _ arguments: [String],
                    onStdoutLine: (@Sendable (String) -> Void)? = nil) async throws -> String {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice

        let stdout = Pipe(), stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let buffers = Buffers()
        stdout.fileHandleForReading.readabilityHandler = { h in
            let data = h.availableData
            guard !data.isEmpty else { return }
            for line in buffers.appendStdout(data) { onStdoutLine?(line) }
        }
        stderr.fileHandleForReading.readabilityHandler = { h in
            let data = h.availableData
            guard !data.isEmpty else { return }
            buffers.appendStderr(data)
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
                process.terminationHandler = { p in
                    stdout.fileHandleForReading.readabilityHandler = nil
                    stderr.fileHandleForReading.readabilityHandler = nil
                    buffers.appendStderr(stderr.fileHandleForReading.readDataToEndOfFile())
                    if p.terminationReason == .uncaughtSignal || Task.isCancelled {
                        cont.resume(throwing: CancellationError())
                    } else if p.terminationStatus == 0 {
                        cont.resume(returning: buffers.stdoutText)
                    } else {
                        cont.resume(throwing: ConvertError.toolFailed(buffers.stderrTail))
                    }
                }
                do {
                    try process.run()
                    if Task.isCancelled { process.terminate() }
                } catch {
                    cont.resume(throwing: error)
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }

    private final class Buffers: @unchecked Sendable {
        private let lock = NSLock()
        private var pending = Data()
        private var allStdout = Data()
        private var err = Data()
        private let maxErr = 8_192

        func appendStdout(_ data: Data) -> [String] {
            lock.lock(); defer { lock.unlock() }
            allStdout.append(data)
            if allStdout.count > 1_000_000 { allStdout = allStdout.suffix(100_000) }
            pending.append(data)
            var lines: [String] = []
            while let nl = pending.firstIndex(of: 0x0A) {
                let lineData = pending[pending.startIndex..<nl]
                pending.removeSubrange(pending.startIndex...nl)
                if let s = String(data: lineData, encoding: .utf8) { lines.append(s) }
            }
            return lines
        }

        func appendStderr(_ data: Data) {
            lock.lock(); defer { lock.unlock() }
            err.append(data)
            if err.count > maxErr { err = err.suffix(maxErr) }
        }

        var stdoutText: String {
            lock.lock(); defer { lock.unlock() }
            return String(data: allStdout, encoding: .utf8) ?? ""
        }

        var stderrTail: String {
            lock.lock(); defer { lock.unlock() }
            let text = String(data: err, encoding: .utf8) ?? ""
            let lines = text.split(separator: "\n").suffix(4).joined(separator: "\n")
            return lines.isEmpty ? "The converter exited with an error." : lines
        }
    }
}
