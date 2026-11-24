import AppKit
import ImageIO
import PDFKit
import Testing
@testable import Convert

/// End-to-end conversions that need no ffmpeg, so they run on any Mac and in CI.
@Suite struct EngineTests {
    private func typeAndWidth(_ url: URL) -> (String?, Int?) {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return (nil, nil) }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        return (CGImageSourceGetType(src) as String?, props?[kCGImagePropertyPixelWidth] as? Int)
    }

    @Test func pngToJpegKeepsTheOriginalAndNeverOverwrites() async throws {
        let dir = try TempDir()
        let input = try dir.png("red.png", width: 4, height: 3)

        let first = try await ImageConverter.convert(input, to: format("jpeg"), quality: .balanced)
        #expect(first.lastPathComponent == "red.jpg")
        let (type, width) = typeAndWidth(first)
        #expect(type == "public.jpeg")
        #expect(width == 4)

        let second = try await ImageConverter.convert(input, to: format("jpeg"), quality: .small)
        #expect(second.lastPathComponent == "red 2.jpg")
        #expect(try dir.listing() == ["red 2.jpg", "red.jpg", "red.png"])
    }

    @Test func imageToPDFAndBackToPNG() async throws {
        let dir = try TempDir()
        let input = try dir.png("red.png")

        let pdf = try await ImageConverter.convert(input, to: format("image-pdf"), quality: .balanced)
        #expect(pdf.lastPathComponent == "red.pdf")
        #expect(PDFDocument(url: pdf)?.pageCount == 1)

        // red.png already exists, so the rendered page must not replace it.
        let pages = try PDFConverter.convert(pdf, to: format("pdf-png"), quality: .small)
        #expect(pages.map(\.lastPathComponent) == ["red 2.png"])
        #expect(typeAndWidth(pages[0]).0 == "public.png")
        #expect(!(try dir.listing().contains { $0.hasPrefix(".convert-") }))
    }

    @MainActor
    @Test func markdownToPlainTextAndHTML() throws {
        let dir = try TempDir()
        let input = try dir.touch("notes.md", contents: "# Hello\n- **one**\n- two")

        let txt = try DocumentConverter.convert(input, to: format("txt"))
        #expect(txt.lastPathComponent == "notes.txt")
        #expect(try String(contentsOf: txt, encoding: .utf8) == "Hello\n•  one\n•  two\n")

        let html = try DocumentConverter.convert(input, to: format("html"))
        let body = try String(contentsOf: html, encoding: .utf8)
        #expect(body.contains("<html") && body.contains("Hello"))
    }

    @MainActor
    @Test func unreadableDocumentThrows() throws {
        let dir = try TempDir()
        let input = dir.file("missing.rtf")
        #expect(throws: ConvertError.self) { try DocumentConverter.convert(input, to: format("txt")) }
        #expect(try dir.listing().isEmpty)
    }
}
