import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct ConvertView: View {
    @ObservedObject var model: ConversionModel
    var close: () -> Void

    var body: some View {
        Group {
            switch model.phase {
            case .empty: dropZone
            case .ready: setup
            case .running: running
            case .finished: finished
            }
        }
        .padding(20)
        .frame(width: 420)
        .onDrop(of: [.fileURL], isTargeted: $model.dropTargeted, perform: handleDrop)
    }

    // MARK: Empty

    private var dropZone: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath.doc.on.clipboard")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
            Text("Drop files or folders here").font(.headline)
            Text("Or right-click any file in Finder and choose **Convert…**")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Choose Files…", action: chooseFiles)
                .keyboardShortcut("o")
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                .foregroundStyle(model.dropTargeted ? Color.accentColor : Color.secondary.opacity(0.4))
        )
    }

    // MARK: Setup

    private var setup: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            Picker("Convert to", selection: $model.format) {
                ForEach(model.availableGroups, id: \.0) { group, formats in
                    Section(group.title) {
                        ForEach(formats) { f in
                            Text(f.label).tag(Optional(f))
                        }
                    }
                }
            }

            if model.skippedCount > 0 {
                Label("\(model.skippedCount) file\(model.skippedCount == 1 ? "" : "s") can't become \(model.format?.label ?? "that") and will be skipped.",
                      systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            DisclosureGroup("Advanced", isExpanded: $model.showAdvanced) {
                Picker("Quality", selection: $model.quality) {
                    ForEach(Quality.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.top, 6)
            }

            HStack {
                Toggle("Move original to Trash", isOn: $model.moveOriginalToTrash)
                    .toggleStyle(.checkbox)
                Spacer()
                Button("Cancel", action: close)
                    .keyboardShortcut(.cancelAction)
                Button("Convert", action: model.start)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.convertibleFiles.isEmpty)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.title).font(.headline).lineLimit(1).truncationMode(.middle)
                Text(model.summary).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var icon: NSImage {
        if model.files.count == 1, let f = model.files.first {
            return NSWorkspace.shared.icon(forFile: f.path)
        }
        return NSWorkspace.shared.icon(for: .folder)
    }

    // MARK: Running

    private var running: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            ProgressView(value: model.progress)
            HStack {
                Text("Converting \(model.currentName)")
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Stop", action: model.cancel)
                    .keyboardShortcut(.cancelAction)
            }
        }
    }

    // MARK: Finished

    private var finished: some View {
        VStack(alignment: .leading, spacing: 12) {
            let ok = model.succeeded.count
            Label(ok > 0 ? "Converted \(ok) file\(ok == 1 ? "" : "s")" : "Nothing was converted",
                  systemImage: ok > 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(ok > 0 ? .green : .orange)

            Text("0 bytes uploaded. Everything stayed on this Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !model.failed.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(model.failed) { r in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.input.lastPathComponent).font(.caption.bold())
                                Text(r.error ?? "").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 140)
            }

            HStack {
                Spacer()
                if ok > 0 {
                    Button("Show in Finder") { model.revealOutputs(); close() }
                }
                Button("Done", action: close)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: Input helpers

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard model.phase == .empty || model.phase == .ready else { return false }
        let group = DispatchGroup()
        let box = URLBox()
        for p in providers {
            group.enter()
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                if let url { box.append(url) }
                group.leave()
            }
        }
        let model = self.model
        group.notify(queue: .main) {
            Task { @MainActor in model.load(box.urls) }
        }
        return true
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        if panel.runModal() == .OK { model.load(panel.urls) }
    }
}

private final class URLBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URL] = []
    func append(_ url: URL) { lock.lock(); storage.append(url); lock.unlock() }
    var urls: [URL] { lock.lock(); defer { lock.unlock() }; return storage }
}
