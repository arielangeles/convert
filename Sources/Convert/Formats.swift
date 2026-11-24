import Foundation
import UniformTypeIdentifiers

/// What kind of thing a file is. Drives which outputs are offered and which engine runs.
enum MediaKind: String, CaseIterable, Identifiable {
    case audio, video, image, document, pdf
    var id: String { rawValue }

    var title: String {
        switch self {
        case .audio: return "Audio"
        case .video: return "Video"
        case .image: return "Image"
        case .document: return "Document"
        case .pdf: return "PDF"
        }
    }
}

enum Quality: String, CaseIterable, Identifiable {
    case high = "High", balanced = "Balanced", small = "Small"
    var id: String { rawValue }
}

/// A target format. `id` is unique; several ids may share an extension (e.g. m4a AAC vs ALAC).
struct OutputFormat: Identifiable, Hashable {
    let id: String
    let label: String
    let ext: String
    /// Group shown in the picker.
    let group: MediaKind
}

enum FormatCatalog {
    static let audio: [OutputFormat] = [
        .init(id: "mp3", label: "MP3", ext: "mp3", group: .audio),
        .init(id: "m4a", label: "M4A (AAC)", ext: "m4a", group: .audio),
        .init(id: "wav", label: "WAV", ext: "wav", group: .audio),
        .init(id: "aiff", label: "AIFF", ext: "aiff", group: .audio),
        .init(id: "flac", label: "FLAC", ext: "flac", group: .audio),
        .init(id: "alac", label: "ALAC (Apple Lossless)", ext: "m4a", group: .audio),
        .init(id: "ogg", label: "OGG Vorbis", ext: "ogg", group: .audio),
        .init(id: "opus", label: "Opus", ext: "opus", group: .audio),
        .init(id: "wma", label: "WMA", ext: "wma", group: .audio),
        .init(id: "ac3", label: "AC3", ext: "ac3", group: .audio),
    ]

    static let video: [OutputFormat] = [
        .init(id: "mp4", label: "MP4 (H.264)", ext: "mp4", group: .video),
        .init(id: "mp4-hevc", label: "MP4 (HEVC, hardware)", ext: "mp4", group: .video),
        .init(id: "mov", label: "MOV", ext: "mov", group: .video),
        .init(id: "m4v", label: "M4V", ext: "m4v", group: .video),
        .init(id: "mkv", label: "MKV", ext: "mkv", group: .video),
        .init(id: "webm", label: "WebM (VP9)", ext: "webm", group: .video),
        .init(id: "avi", label: "AVI", ext: "avi", group: .video),
        .init(id: "wmv", label: "WMV", ext: "wmv", group: .video),
        .init(id: "gif-anim", label: "Animated GIF", ext: "gif", group: .video),
    ]

    static let image: [OutputFormat] = [
        .init(id: "jpeg", label: "JPEG", ext: "jpg", group: .image),
        .init(id: "png", label: "PNG", ext: "png", group: .image),
        .init(id: "heic", label: "HEIC", ext: "heic", group: .image),
        .init(id: "tiff", label: "TIFF", ext: "tiff", group: .image),
        .init(id: "gif", label: "GIF", ext: "gif", group: .image),
        .init(id: "bmp", label: "BMP", ext: "bmp", group: .image),
        .init(id: "jp2", label: "JPEG 2000", ext: "jp2", group: .image),
        .init(id: "webp", label: "WebP", ext: "webp", group: .image),
        .init(id: "tga", label: "TGA", ext: "tga", group: .image),
        .init(id: "psd", label: "PSD", ext: "psd", group: .image),
        .init(id: "ico", label: "ICO", ext: "ico", group: .image),
        .init(id: "image-pdf", label: "PDF", ext: "pdf", group: .image),
    ]

    static let document: [OutputFormat] = [
        .init(id: "docx", label: "Word (DOCX)", ext: "docx", group: .document),
        .init(id: "doc", label: "Word 97 (DOC)", ext: "doc", group: .document),
        .init(id: "odt", label: "OpenDocument (ODT)", ext: "odt", group: .document),
        .init(id: "rtf", label: "Rich Text (RTF)", ext: "rtf", group: .document),
        .init(id: "html", label: "HTML", ext: "html", group: .document),
        .init(id: "txt", label: "Plain text", ext: "txt", group: .document),
        .init(id: "webarchive", label: "Web Archive", ext: "webarchive", group: .document),
        .init(id: "doc-pdf", label: "PDF", ext: "pdf", group: .document),
    ]

    static let pdf: [OutputFormat] = [
        .init(id: "pdf-png", label: "PNG (one per page)", ext: "png", group: .pdf),
        .init(id: "pdf-jpeg", label: "JPEG (one per page)", ext: "jpg", group: .pdf),
        .init(id: "pdf-tiff", label: "TIFF (multi-page)", ext: "tiff", group: .pdf),
        .init(id: "pdf-txt", label: "Plain text", ext: "txt", group: .pdf),
    ]

    static var all: [OutputFormat] { audio + video + image + document + pdf }

    /// Which outputs a given input kind can produce.
    static func outputs(for kind: MediaKind) -> [OutputFormat] {
        switch kind {
        case .audio: return audio
        case .video: return video + audio   // video can also be turned into audio
        case .image: return image
        case .document: return document
        case .pdf: return pdf
        }
    }

    static func canConvert(_ kind: MediaKind, to format: OutputFormat) -> Bool {
        outputs(for: kind).contains(format)
    }

    /// Sensible default for a batch, avoiding "convert X to X".
    static func defaultFormat(for kind: MediaKind, inputExt: String) -> OutputFormat? {
        let preferred: [String]
        switch kind {
        case .audio: preferred = ["mp3", "m4a"]
        case .video: preferred = ["mp4", "mov"]
        case .image: preferred = ["jpeg", "png"]
        case .document: preferred = ["docx", "doc-pdf"]
        case .pdf: preferred = ["pdf-png", "pdf-txt"]
        }
        let options = outputs(for: kind)
        let ext = inputExt.lowercased()
        for id in preferred {
            if let f = options.first(where: { $0.id == id }), f.ext != ext && !(ext == "jpeg" && f.ext == "jpg") {
                return f
            }
        }
        return options.first
    }
}

enum MediaClassifier {
    // UTType doesn't know some common extensions on every macOS version, so check these first.
    private static let audioExts: Set<String> = ["opus", "ogg", "oga", "flac", "wma", "ac3", "mp2", "amr", "ape", "wv", "m4a", "aac", "caf", "mka", "aiff", "aif", "wav", "mp3"]
    private static let videoExts: Set<String> = ["mkv", "webm", "avi", "wmv", "flv", "ts", "mts", "m2ts", "3gp", "ogv", "vob", "mov", "mp4", "m4v", "mpg", "mpeg"]
    private static let imageExts: Set<String> = ["webp", "avif", "heic", "heif", "tga", "psd", "jp2", "bmp", "ico", "dng", "cr2", "nef", "arw"]
    private static let documentExts: Set<String> = ["doc", "docx", "odt", "md", "markdown", "txt", "rtf", "html", "htm", "webarchive"]

    static func kind(of url: URL) -> MediaKind? {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" { return .pdf }
        if audioExts.contains(ext) { return .audio }
        if videoExts.contains(ext) { return .video }
        if imageExts.contains(ext) { return .image }
        if documentExts.contains(ext) { return .document }

        guard let type = UTType(filenameExtension: ext) else { return nil }
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .movie) { return .video }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .rtf) || type.conforms(to: .html) || type.conforms(to: .plainText) { return .document }
        return nil
    }

    /// Expands folders (recursively) into the files inside them we know how to handle.
    static func expand(_ urls: [URL], limit: Int = 5_000) -> [URL] {
        var result: [URL] = []
        let fm = FileManager.default
        for url in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue && !isPackage(url) {
                let keys: [URLResourceKey] = [.isRegularFileKey]
                guard let e = fm.enumerator(at: url, includingPropertiesForKeys: keys,
                                            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
                for case let file as URL in e {
                    guard (try? file.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
                    if kind(of: file) != nil { result.append(file) }
                    if result.count >= limit { return result }
                }
            } else if kind(of: url) != nil {
                result.append(url)
            }
        }
        return result
    }

    private static func isPackage(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isPackageKey]))?.isPackage ?? false
    }
}
