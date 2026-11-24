import AppKit
import Foundation

struct FileResult: Identifiable {
    let id = UUID()
    let input: URL
    let outputs: [URL]
    let error: String?
}

@MainActor
final class ConversionModel: ObservableObject {
    enum Phase: Equatable {
        case empty
        case ready
        case running
        case finished
    }

    @Published private(set) var files: [URL] = []
    @Published private(set) var phase: Phase = .empty
    @Published var format: OutputFormat?
    @Published var quality: Quality {
        didSet { UserDefaults.standard.set(quality.rawValue, forKey: "quality") }
    }
    @Published var moveOriginalToTrash: Bool {
        didSet { UserDefaults.standard.set(moveOriginalToTrash, forKey: "moveOriginalToTrash") }
    }
    @Published private(set) var progress: Double = 0
    @Published private(set) var currentName = ""
    @Published private(set) var results: [FileResult] = []
    // View-only UI state. Kept here rather than in @State because @State is a macro that
    // needs Xcode's SwiftUIMacros plugin, which the Command Line Tools don't ship.
    @Published var showAdvanced = false
    @Published var dropTargeted = false

    private var task: Task<Void, Never>?
    private var fractions: [URL: Double] = [:]

    init(urls: [URL] = []) {
        quality = Quality(rawValue: UserDefaults.standard.string(forKey: "quality") ?? "") ?? .balanced
        moveOriginalToTrash = UserDefaults.standard.bool(forKey: "moveOriginalToTrash")
        if !urls.isEmpty { load(urls) }
    }

    // MARK: Inputs

    func load(_ urls: [URL]) {
        let expanded = MediaClassifier.expand(urls)
        files = expanded
        results = []
        progress = 0
        phase = expanded.isEmpty ? .empty : .ready
        format = defaultFormat()
    }

    var kinds: [MediaKind] {
        let present = Set(files.compactMap(MediaClassifier.kind(of:)))
        return MediaKind.allCases.filter(present.contains)
    }

    /// Output groups to show in the picker: anything at least one input can become.
    var availableGroups: [(MediaKind, [OutputFormat])] {
        let outputs = Set(kinds.flatMap(FormatCatalog.outputs(for:)))
        return MediaKind.allCases.compactMap { group in
            let items = FormatCatalog.all.filter { $0.group == group && outputs.contains($0) }
            return items.isEmpty ? nil : (group, items)
        }
    }

    var convertibleFiles: [URL] {
        guard let format else { return [] }
        return files.filter { url in
            MediaClassifier.kind(of: url).map { FormatCatalog.canConvert($0, to: format) } ?? false
        }
    }

    var skippedCount: Int { files.count - convertibleFiles.count }

    var summary: String {
        if files.count == 1, let f = files.first {
            let kind = MediaClassifier.kind(of: f)?.title ?? "File"
            return "\(kind) · \(Self.size(of: f))"
        }
        let counts = Dictionary(grouping: files, by: { MediaClassifier.kind(of: $0)?.title ?? "Other" })
            .map { "\($0.value.count) \($0.key.lowercased())" }
            .sorted()
        return "\(files.count) files · " + counts.joined(separator: ", ")
    }

    var title: String { files.count == 1 ? files[0].lastPathComponent : "\(files.count) files" }

    private func defaultFormat() -> OutputFormat? {
        // Use the most common kind in the batch.
        var byKind: [MediaKind: [URL]] = [:]
        for url in files {
            if let kind = MediaClassifier.kind(of: url) { byKind[kind, default: []].append(url) }
        }
        guard let top = byKind.max(by: { $0.value.count < $1.value.count }) else { return nil }
        return FormatCatalog.defaultFormat(for: top.key, inputExt: top.value[0].pathExtension)
    }

    // MARK: Running

    func start() {
        guard let format, phase == .ready else { return }
        let jobs = convertibleFiles
        guard !jobs.isEmpty else { return }
        let options = ConversionOptions(quality: quality, moveOriginalToTrash: moveOriginalToTrash)

        phase = .running
        progress = 0
        fractions = [:]
        results = []
        currentName = jobs[0].lastPathComponent

        // Heavy media runs 2 at a time (ffmpeg is already multi-threaded); light work 4.
        let heavy = jobs.contains { url in
            let kind = MediaClassifier.kind(of: url)
            return kind == .audio || kind == .video
        }
        let width = heavy ? 2 : 4

        task = Task { [self] in
            await withTaskGroup(of: FileResult.self) { group in
                var pending = jobs.makeIterator()
                for _ in 0..<width {
                    guard let url = pending.next() else { break }
                    group.addTask { await Self.run(url, format: format, options: options, model: self) }
                }
                for await result in group {
                    finish(result, total: jobs.count)
                    if Task.isCancelled {
                        group.cancelAll()
                    } else if let url = pending.next() {
                        group.addTask { await Self.run(url, format: format, options: options, model: self) }
                    }
                }
            }
            phase = .finished
        }
    }

    private nonisolated static func run(_ url: URL, format: OutputFormat, options: ConversionOptions,
                                        model: ConversionModel) async -> FileResult {
        do {
            let outs = try await Converter.convert(url, to: format, options: options) { p in
                Task { @MainActor in model.report(url, p) }
            }
            return FileResult(input: url, outputs: outs, error: nil)
        } catch is CancellationError {
            return FileResult(input: url, outputs: [], error: "Cancelled")
        } catch {
            return FileResult(input: url, outputs: [], error: error.localizedDescription)
        }
    }

    func cancel() {
        task?.cancel()
    }

    private func report(_ url: URL, _ fraction: Double) {
        guard phase == .running else { return }
        fractions[url] = fraction
        currentName = url.lastPathComponent
        let total = Double(max(convertibleFiles.count, 1))
        progress = min(fractions.values.reduce(0, +) / total, 1)
    }

    private func finish(_ result: FileResult, total: Int) {
        results.append(result)
        fractions[result.input] = 1
        progress = min(fractions.values.reduce(0, +) / Double(max(total, 1)), 1)
    }

    // MARK: Results

    var succeeded: [FileResult] { results.filter { $0.error == nil } }
    var failed: [FileResult] { results.filter { $0.error != nil && $0.error != "Cancelled" } }
    var wasCancelled: Bool { results.contains { $0.error == "Cancelled" } || results.count < convertibleFiles.count }

    func revealOutputs() {
        let outs = succeeded.flatMap(\.outputs)
        if !outs.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(outs) }
    }

    func reset() {
        files = []
        results = []
        phase = .empty
    }

    private static func size(of url: URL) -> String {
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
