import AppKit
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

struct ConversionOptions {
    var quality: Quality = .balanced
    var moveOriginalToTrash = false
}

/// Converts one file. Everything happens locally: ffmpeg for audio/video, ImageIO for images,
/// AppKit's text system for documents, PDFKit for PDFs.
enum Converter {
    /// Returns the files written. `progress` reports 0...1 for this file.
    static func convert(_ input: URL,
                        to format: OutputFormat,
                        options: ConversionOptions,
                        progress: @escaping @Sendable (Double) -> Void) async throws -> [URL] {
        guard let kind = MediaClassifier.kind(of: input), FormatCatalog.canConvert(kind, to: format) else {
            throw ConvertError.unsupported("\(input.lastPathComponent) can't be converted to \(format.label).")
        }

        let outputs: [URL]
        switch kind {
        case .audio, .video:
            outputs = [try await FFmpeg.convert(input, to: format, quality: options.quality, progress: progress)]
        case .image:
            outputs = [try await ImageConverter.convert(input, to: format, quality: options.quality)]
        case .document:
            outputs = [try await DocumentConverter.convert(input, to: format)]
        case .pdf:
            outputs = try PDFConverter.convert(input, to: format, quality: options.quality)
        }
        progress(1)

        if options.moveOriginalToTrash, !outputs.isEmpty {
            try? FileManager.default.trashItem(at: input, resultingItemURL: nil)
        }
        return outputs
    }

    /// "Interview.mp3", or "Interview 2.mp3" if that already exists. Never overwrites.
    static func uniqueOutputURL(for input: URL, ext: String, suffix: String = "") -> URL {
        let dir = input.deletingLastPathComponent()
        let base = input.deletingPathExtension().lastPathComponent + suffix
        var candidate = dir.appendingPathComponent(base).appendingPathExtension(ext)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(base) \(n)").appendingPathExtension(ext)
            n += 1
        }
        return candidate
    }

    /// Writes to a hidden temp file next to the destination, then moves it into place,
    /// so a failed or cancelled conversion never leaves a half-written file behind.
    static func atomicWrite(to dest: URL, _ body: (URL) async throws -> Void) async throws {
        let tmp = tempURL(for: dest)
        do {
            try await body(tmp)
            try FileManager.default.moveItem(at: tmp, to: dest)
        } catch {
            try? FileManager.default.removeItem(at: tmp)
            throw error
        }
    }

    /// Synchronous variant; runs on the caller's actor (needed for AppKit text/printing work).
    static func atomicWriteSync(to dest: URL, _ body: (URL) throws -> Void) throws {
        let tmp = tempURL(for: dest)
        do {
            try body(tmp)
            try FileManager.default.moveItem(at: tmp, to: dest)
        } catch {
            try? FileManager.default.removeItem(at: tmp)
            throw error
        }
    }

    private static func tempURL(for dest: URL) -> URL {
        dest.deletingLastPathComponent()
            .appendingPathComponent(".convert-\(UUID().uuidString)")
            .appendingPathExtension(dest.pathExtension)
    }
}

// MARK: - Audio / video

enum FFmpeg {
    static func convert(_ input: URL, to format: OutputFormat, quality: Quality,
                        progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        guard let ffmpeg = ToolLocator.find("ffmpeg") else { throw ConvertError.ffmpegMissing }
        let duration = await probeDuration(input, ffmpeg: ffmpeg)
        let dest = Converter.uniqueOutputURL(for: input, ext: format.ext)

        try await Converter.atomicWrite(to: dest) { tmp in
            var args = ["-hide_banner", "-nostdin", "-y", "-progress", "pipe:1", "-nostats", "-i", input.path]
            args += codecArgs(for: format, quality: quality, encoders: await encoders(ffmpeg))
            args += ["-map_metadata", "0", tmp.path]

            try await ProcessRunner.run(ffmpeg, args) { line in
                guard let duration, duration > 0, line.hasPrefix("out_time_us=") || line.hasPrefix("out_time_ms=") else { return }
                // Both keys are microseconds in current ffmpeg builds.
                if let us = Double(line.split(separator: "=").last ?? "") {
                    progress(min(max(us / 1_000_000 / duration, 0), 0.99))
                }
            }
        }
        return dest
    }

    private static func probeDuration(_ input: URL, ffmpeg: URL) async -> Double? {
        let ffprobe = ffmpeg.deletingLastPathComponent().appendingPathComponent("ffprobe")
        guard FileManager.default.isExecutableFile(atPath: ffprobe.path) else { return nil }
        let out = try? await ProcessRunner.run(ffprobe, ["-v", "error", "-show_entries", "format=duration",
                                                         "-of", "default=nw=1:nk=1", input.path])
        return out.flatMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    private static let encoderCache = EncoderCache()

    /// Encoder names this ffmpeg build offers (`ffmpeg -encoders`), cached per binary.
    /// nil if the list couldn't be read; callers then assume the usual Homebrew encoders.
    static func encoders(_ ffmpeg: URL) async -> Set<String>? {
        if let cached = encoderCache.get(ffmpeg) { return cached }
        guard let out = try? await ProcessRunner.run(ffmpeg, ["-hide_banner", "-encoders"]) else { return nil }
        // Lines look like " A....D libmp3lame           libmp3lame MP3 (MPEG audio layer 3)".
        let names = Set(out.split(separator: "\n").compactMap { line -> String? in
            let cols = line.split(separator: " ", omittingEmptySubsequences: true)
            guard cols.count >= 2, cols[0].count == 6, cols[0].allSatisfy({ "VASFXBD.".contains($0) }) else { return nil }
            return String(cols[1])
        })
        guard !names.isEmpty else { return nil }
        encoderCache.set(ffmpeg, names)
        return names
    }

    /// `encoders`: what this ffmpeg build offers; nil means unknown (assume the usual ones).
    static func codecArgs(for format: OutputFormat, quality: Quality, encoders: Set<String>? = nil) -> [String] {
        func pick<T>(_ high: T, _ balanced: T, _ small: T) -> T {
            switch quality { case .high: return high; case .balanced: return balanced; case .small: return small }
        }
        let h264 = ["-c:v", "libx264", "-preset", "medium", "-crf", pick("18", "23", "28"), "-pix_fmt", "yuv420p"]
        let aac = ["-c:a", "aac", "-b:a", pick("256k", "192k", "128k")]

        switch format.id {
        // Audio (drop any video/cover-art stream)
        case "mp3":  return ["-vn", "-c:a", "libmp3lame", "-b:a", pick("320k", "192k", "128k")]
        case "m4a":  return ["-vn"] + aac
        case "wav":  return ["-vn", "-c:a", "pcm_s16le"]
        case "aiff": return ["-vn", "-c:a", "pcm_s16be"]
        case "flac": return ["-vn", "-c:a", "flac"]
        case "alac": return ["-vn", "-c:a", "alac"]
        case "ogg":
            // Homebrew's ffmpeg dropped libvorbis (2025). ffmpeg's own Vorbis encoder is marked
            // experimental, only takes stereo and mostly ignores quality, but it works.
            if let encoders, !encoders.contains("libvorbis") {
                return ["-vn", "-c:a", "vorbis", "-strict", "experimental", "-ac", "2"]
            }
            return ["-vn", "-c:a", "libvorbis", "-q:a", pick("8", "5", "3")]
        case "opus": return ["-vn", "-c:a", "libopus", "-b:a", pick("192k", "128k", "64k")]
        case "wma":  return ["-vn", "-c:a", "wmav2", "-b:a", pick("192k", "128k", "96k")]
        case "ac3":  return ["-vn", "-c:a", "ac3", "-b:a", pick("448k", "384k", "192k")]

        // Video
        case "mp4", "m4v": return h264 + aac + ["-movflags", "+faststart"]
        case "mp4-hevc":
            return ["-c:v", "hevc_videotoolbox", "-q:v", pick("70", "58", "45"), "-tag:v", "hvc1"] + aac + ["-movflags", "+faststart"]
        case "mov":  return h264 + aac
        case "mkv":  return h264 + aac
        case "webm":
            return ["-c:v", "libvpx-vp9", "-crf", pick("24", "32", "40"), "-b:v", "0", "-row-mt", "1",
                    "-c:a", "libopus", "-b:a", pick("160k", "128k", "96k")]
        case "avi":  return ["-c:v", "mpeg4", "-q:v", pick("2", "4", "8"), "-c:a", "libmp3lame", "-b:a", "192k"]
        case "wmv":  return ["-c:v", "wmv2", "-q:v", pick("2", "4", "8"), "-c:a", "wmav2", "-b:a", "192k"]
        case "gif-anim":
            let fps = pick("15", "12", "10"), width = pick("960", "640", "480")
            return ["-an", "-vf", "fps=\(fps),scale='min(\(width),iw)':-2:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer",
                    "-loop", "0"]
        default: return []
        }
    }
}

private final class EncoderCache: @unchecked Sendable {
    private let lock = NSLock()
    private var byPath: [String: Set<String>] = [:]
    func get(_ url: URL) -> Set<String>? { lock.lock(); defer { lock.unlock() }; return byPath[url.path] }
    func set(_ url: URL, _ names: Set<String>) { lock.lock(); byPath[url.path] = names; lock.unlock() }
}

// MARK: - Images

enum ImageConverter {
    private static let utTypes: [String: UTType] = [
        "jpeg": .jpeg, "png": .png, "heic": .heic, "tiff": .tiff, "gif": .gif, "bmp": .bmp,
        "jp2": UTType("public.jpeg-2000") ?? .image, "tga": UTType("com.truevision.tga-image") ?? .image,
        "psd": UTType("com.adobe.photoshop-image") ?? .image, "ico": .ico,
    ]

    static func convert(_ input: URL, to format: OutputFormat, quality: Quality) async throws -> URL {
        let dest = Converter.uniqueOutputURL(for: input, ext: format.ext)

        if format.id == "image-pdf" {
            try Converter.atomicWriteSync(to: dest) { tmp in try imageToPDF(input, tmp) }
            return dest
        }

        // Prefer ImageIO (in-process, keeps metadata). Fall back to ffmpeg for formats
        // ImageIO can't write on this macOS version (WebP on most).
        if let type = utTypes[format.id], canWrite(type) {
            try Converter.atomicWriteSync(to: dest) { tmp in try writeWithImageIO(input, tmp, type: type, quality: quality) }
            return dest
        }
        if format.id == "webp" {
            try await Converter.atomicWrite(to: dest) { tmp in try await webpViaFFmpeg(input, tmp, quality: quality) }
            return dest
        }
        throw ConvertError.unsupported("This Mac can't write \(format.label) images.")
    }

    private static func canWrite(_ type: UTType) -> Bool {
        let writable = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        return writable.contains(type.identifier)
    }

    private static func lossyQuality(_ q: Quality) -> Double {
        switch q { case .high: return 0.92; case .balanced: return 0.8; case .small: return 0.6 }
    }

    private static func writeWithImageIO(_ input: URL, _ output: URL, type: UTType, quality: Quality) throws {
        guard let source = CGImageSourceCreateWithURL(input as CFURL, nil) else {
            throw ConvertError.unreadable(input.lastPathComponent)
        }
        let total = CGImageSourceGetCount(source)
        // Keep every frame for formats that support it (GIF → TIFF, animated GIF → GIF); otherwise the first.
        let multiFrame: Set<UTType> = [.gif, .tiff]
        let frames = (multiFrame.contains(type) && total > 1) ? total : 1

        guard let dest = CGImageDestinationCreateWithURL(output as CFURL, type.identifier as CFString, frames, nil) else {
            throw ConvertError.unsupported("Couldn't create a \(type.preferredFilenameExtension ?? "image") file.")
        }
        let props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: lossyQuality(quality)]
        for i in 0..<frames {
            // AddImageFromSource carries over EXIF/orientation/colour profile.
            CGImageDestinationAddImageFromSource(dest, source, i, props as CFDictionary)
        }
        guard CGImageDestinationFinalize(dest) else {
            throw ConvertError.toolFailed("Couldn't write \(output.pathExtension.uppercased()).")
        }
    }

    private static func imageToPDF(_ input: URL, _ output: URL) throws {
        guard let image = NSImage(contentsOf: input), let page = PDFPage(image: image) else {
            throw ConvertError.unreadable(input.lastPathComponent)
        }
        let doc = PDFDocument()
        doc.insert(page, at: 0)
        guard doc.write(to: output) else { throw ConvertError.toolFailed("Couldn't write PDF.") }
    }

    private static func webpViaFFmpeg(_ input: URL, _ output: URL, quality: Quality) async throws {
        guard let ffmpeg = ToolLocator.find("ffmpeg") else { throw ConvertError.ffmpegMissing }
        // ffmpeg's HEIC support is patchy, so decode with ImageIO first.
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: staging) }
        try writeWithImageIO(input, staging, type: .png, quality: .high)
        let q: String = { switch quality { case .high: return "90"; case .balanced: return "80"; case .small: return "65" } }()
        try await ProcessRunner.run(ffmpeg, ["-hide_banner", "-nostdin", "-y", "-i", staging.path,
                                             "-c:v", "libwebp", "-quality", q, "-f", "webp", output.path])
    }
}

// MARK: - Documents

@MainActor
enum DocumentConverter {
    static func convert(_ input: URL, to format: OutputFormat) throws -> URL {
        let text = try load(input)
        let dest = Converter.uniqueOutputURL(for: input, ext: format.ext)

        try Converter.atomicWriteSync(to: dest) { tmp in
            if format.id == "doc-pdf" {
                try writePDF(text, to: tmp)
                return
            }
            let type: NSAttributedString.DocumentType
            switch format.id {
            case "docx": type = .officeOpenXML
            case "doc": type = .docFormat
            case "odt": type = .openDocument
            case "rtf": type = .rtf
            case "html": type = .html
            case "txt": type = .plain
            case "webarchive": type = .webArchive
            default: throw ConvertError.unsupported("Unknown document format \(format.label).")
            }
            let data = try text.data(from: NSRange(location: 0, length: text.length),
                                     documentAttributes: [.documentType: type, .characterEncoding: String.Encoding.utf8.rawValue])
            try data.write(to: tmp)
        }
        return dest
    }

    private static func load(_ url: URL) throws -> NSAttributedString {
        let ext = url.pathExtension.lowercased()
        if ext == "md" || ext == "markdown" {
            let raw = try String(contentsOf: url, encoding: .utf8)
            return Markdown.render(raw)
        }
        do {
            return try NSAttributedString(url: url, options: [:], documentAttributes: nil)
        } catch {
            throw ConvertError.unreadable(url.lastPathComponent)
        }
    }

    private static func writePDF(_ text: NSAttributedString, to url: URL) throws {
        let info = NSPrintInfo(dictionary: [.jobSavingURL: url])
        info.jobDisposition = .save
        info.paperSize = NSSize(width: 612, height: 792) // US Letter
        info.topMargin = 54; info.bottomMargin = 54; info.leftMargin = 54; info.rightMargin = 54
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic

        let width = info.paperSize.width - info.leftMargin - info.rightMargin
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 1))
        view.textStorage?.setAttributedString(text)
        view.isVerticallyResizable = true
        view.textContainer?.widthTracksTextView = true
        view.sizeToFit()

        let op = NSPrintOperation(view: view, printInfo: info)
        op.showsPrintPanel = false
        op.showsProgressPanel = false
        guard op.run(), FileManager.default.fileExists(atPath: url.path) else {
            throw ConvertError.toolFailed("Couldn't write PDF.")
        }
    }
}

/// Small Markdown → rich text renderer: headings, bullets, quotes and code blocks at the block
/// level, with Foundation's parser handling inline bold/italic/code/links.
enum Markdown {
    static func render(_ source: String) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let body = NSFont.systemFont(ofSize: 13)
        let mono = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        var inCode = false

        for rawLine in source.components(separatedBy: .newlines) {
            let line = rawLine
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") { inCode.toggle(); continue }
            if inCode {
                out.append(NSAttributedString(string: line + "\n", attributes: [.font: mono]))
                continue
            }

            var font = body
            var text = line
            var prefix = ""
            if let m = line.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
                let level = line[m].filter { $0 == "#" }.count
                font = NSFont.boldSystemFont(ofSize: [24, 20, 17, 15, 14, 13][level - 1])
                text = String(line[m.upperBound...])
            } else if let m = line.range(of: #"^\s*[-*+]\s+"#, options: .regularExpression) {
                prefix = "•  "
                text = String(line[m.upperBound...])
            } else if let m = line.range(of: #"^>\s?"#, options: .regularExpression) {
                font = NSFontManager.shared.convert(body, toHaveTrait: .italicFontMask)
                text = String(line[m.upperBound...])
            }

            let inline = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                ?? AttributedString(text)
            let ns = NSMutableAttributedString(string: prefix, attributes: [.font: font])
            let rendered = NSMutableAttributedString(attributedString: NSAttributedString(inline))
            // Apply base font while keeping inline bold/italic intent.
            rendered.enumerateAttribute(.inlinePresentationIntent, in: NSRange(location: 0, length: rendered.length)) { value, range, _ in
                var f = font
                if let raw = value as? UInt {
                    let intent = InlinePresentationIntent(rawValue: raw)
                    if intent.contains(.stronglyEmphasized) { f = NSFontManager.shared.convert(f, toHaveTrait: .boldFontMask) }
                    if intent.contains(.emphasized) { f = NSFontManager.shared.convert(f, toHaveTrait: .italicFontMask) }
                    if intent.contains(.code) { f = mono }
                }
                rendered.addAttribute(.font, value: f, range: range)
            }
            ns.append(rendered)
            ns.append(NSAttributedString(string: "\n", attributes: [.font: font]))
            out.append(ns)
        }
        return out
    }
}

// MARK: - PDF

enum PDFConverter {
    static func convert(_ input: URL, to format: OutputFormat, quality: Quality) throws -> [URL] {
        guard let doc = PDFDocument(url: input) else { throw ConvertError.unreadable(input.lastPathComponent) }

        if format.id == "pdf-txt" {
            let dest = Converter.uniqueOutputURL(for: input, ext: "txt")
            try Converter.atomicWriteSync(to: dest) { tmp in
                try (doc.string ?? "").write(to: tmp, atomically: false, encoding: .utf8)
            }
            return [dest]
        }

        let scale: CGFloat = { switch quality { case .high: return 3; case .balanced: return 2; case .small: return 1 } }()
        let type: UTType = format.id == "pdf-jpeg" ? .jpeg : (format.id == "pdf-tiff" ? .tiff : .png)

        if type == .tiff {
            // One multi-page TIFF.
            let dest = Converter.uniqueOutputURL(for: input, ext: "tiff")
            try Converter.atomicWriteSync(to: dest) { tmp in
                guard let d = CGImageDestinationCreateWithURL(tmp as CFURL, type.identifier as CFString, doc.pageCount, nil) else {
                    throw ConvertError.toolFailed("Couldn't create TIFF.")
                }
                for i in 0..<doc.pageCount {
                    try Task.checkCancellation()
                    if let page = doc.page(at: i), let img = render(page, scale: scale) { CGImageDestinationAddImage(d, img, nil) }
                }
                guard CGImageDestinationFinalize(d) else { throw ConvertError.toolFailed("Couldn't write TIFF.") }
            }
            return [dest]
        }

        var outputs: [URL] = []
        for i in 0..<doc.pageCount {
            try Task.checkCancellation()
            guard let page = doc.page(at: i), let img = render(page, scale: scale) else { continue }
            let suffix = doc.pageCount > 1 ? "-p\(i + 1)" : ""
            let dest = Converter.uniqueOutputURL(for: input, ext: format.ext, suffix: suffix)
            try Converter.atomicWriteSync(to: dest) { tmp in
                guard let d = CGImageDestinationCreateWithURL(tmp as CFURL, type.identifier as CFString, 1, nil) else {
                    throw ConvertError.toolFailed("Couldn't create image.")
                }
                CGImageDestinationAddImage(d, img, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
                guard CGImageDestinationFinalize(d) else { throw ConvertError.toolFailed("Couldn't write image.") }
            }
            outputs.append(dest)
        }
        return outputs
    }

    private static func render(_ page: PDFPage, scale: CGFloat) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        let size = NSSize(width: bounds.width * scale, height: bounds.height * scale)
        let image = page.thumbnail(of: size, for: .mediaBox)
        var rect = NSRect(origin: .zero, size: size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}
