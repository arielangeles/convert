import Testing
@testable import Convert

@Suite struct FormatCatalogTests {
    @Test func idsAreUnique() {
        let ids = FormatCatalog.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func eachListHoldsOnlyItsOwnGroup() {
        let lists: [(MediaKind, [OutputFormat])] = [
            (.audio, FormatCatalog.audio), (.video, FormatCatalog.video), (.image, FormatCatalog.image),
            (.document, FormatCatalog.document), (.pdf, FormatCatalog.pdf),
        ]
        for (kind, list) in lists {
            #expect(!list.isEmpty, "\(kind) has no formats")
            #expect(list.allSatisfy { $0.group == kind }, "\(kind) list has a format from another group")
        }
    }

    @Test func extensionsAreLowercaseWithoutDots() {
        for f in FormatCatalog.all {
            #expect(!f.ext.isEmpty && f.ext == f.ext.lowercased() && !f.ext.contains("."), "\(f.id): \(f.ext)")
        }
    }

    @Test func videoCanAlsoBecomeAudio() {
        let outputs = FormatCatalog.outputs(for: .video)
        for f in FormatCatalog.audio { #expect(outputs.contains(f)) }
        #expect(FormatCatalog.canConvert(.video, to: format("mp3")))
        #expect(!FormatCatalog.canConvert(.audio, to: format("mp4")))
        #expect(!FormatCatalog.canConvert(.image, to: format("mp3")))
    }

    @Test(arguments: [
        (MediaKind.audio, "mp3", "m4a"),
        (.audio, "wav", "mp3"),
        (.video, "mp4", "mov"),
        (.video, "mkv", "mp4"),
        (.image, "jpeg", "png"),
        (.image, "JPG", "png"),
        (.image, "png", "jpeg"),
        (.document, "docx", "doc-pdf"),
        (.document, "md", "docx"),
        (.pdf, "pdf", "pdf-png"),
    ])
    func defaultFormatAvoidsSameExtension(kind: MediaKind, inputExt: String, expected: String) {
        #expect(FormatCatalog.defaultFormat(for: kind, inputExt: inputExt)?.id == expected)
    }
}
