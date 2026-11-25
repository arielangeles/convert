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

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
                // Finish only after the process has exited AND both pipes are read to EOF.
                // (readabilityHandler plus a terminationHandler loses output that arrives just
                // before exit: ffprobe's whole answer, under load.)
                let finished = DispatchGroup()
                finished.enter()
                process.terminationHandler = { _ in finished.leave() }
                do {
                    try process.run()
                } catch {
                    cont.resume(throwing: error)
                    return
                }
                drain(stdout.fileHandleForReading, into: finished) { data in
                    for line in buffers.appendStdout(data) { onStdoutLine?(line) }
                }
                drain(stderr.fileHandleForReading, into: finished) { buffers.appendStderr($0) }
                if Task.isCancelled {
                    buffers.markCancelled()
                    process.terminate()
                }

                finished.notify(queue: .global(qos: .utility)) {
                    if let last = buffers.flushStdout() { onStdoutLine?(last) }
                    // ffmpeg catches SIGTERM and exits with an error status rather than dying from
                    // the signal, so a Stop is recognised by our own flag, not the exit reason.
                    if buffers.isCancelled {
                        cont.resume(throwing: CancellationError())
                    } else if process.terminationReason == .exit && process.terminationStatus == 0 {
                        cont.resume(returning: buffers.stdoutText)
                    } else {
                        cont.resume(throwing: ConvertError.toolFailed(buffers.stderrTail))
                    }
                }
            }
        } onCancel: {
            buffers.markCancelled()
            if process.isRunning { process.terminate() }
        }
    }

    /// Reads a pipe on a background thread until EOF (the child exited and closed its end).
    /// Uses read(2), which returns as soon as any bytes arrive, so progress lines stream live.
    /// (FileHandle.read(upToCount:) waits for the full count, which stalls progress.)
    private static func drain(_ handle: FileHandle, into group: DispatchGroup,
                              _ onData: @escaping @Sendable (Data) -> Void) {
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            let fd = handle.fileDescriptor
            var buffer = [UInt8](repeating: 0, count: 65_536)
            while true {
                let n = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
                if n > 0 {
                    onData(Data(buffer[0..<n]))
                } else if n < 0 && errno == EINTR {
                    continue
                } else {
                    break // 0 = EOF, or a read error
                }
            }
            withExtendedLifetime(handle) {}
            group.leave()
        }
    }

    private final class Buffers: @unchecked Sendable {
        private let lock = NSLock()
        private var pending = Data()
        private var allStdout = Data()
        private var err = Data()
        private let maxErr = 8_192
        private var cancelled = false

        func markCancelled() {
            lock.lock(); cancelled = true; lock.unlock()
        }

        var isCancelled: Bool {
            lock.lock(); defer { lock.unlock() }
            return cancelled
        }

        /// The last stdout line if it had no trailing newline.
        func flushStdout() -> String? {
            lock.lock(); defer { lock.unlock() }
            guard !pending.isEmpty else { return nil }
            defer { pending.removeAll() }
            return String(data: pending, encoding: .utf8)
        }

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
