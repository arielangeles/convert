import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Convert

/// Which WebP writer gets picked. Pure, so it runs everywhere.
@Suite struct WebPBackendTests {
    let ffmpeg = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
    let cwebp = URL(fileURLWithPath: "/opt/homebrew/bin/cwebp")

    @Test func imageIOWinsWhenItCanWrite() {
        #expect(ImageConverter.webpBackend(imageIOCanWrite: true, ffmpeg: ffmpeg, ffmpegEncoders: ["libwebp"],
                                           cwebp: cwebp) == .imageIO)
    }

    @Test func ffmpegWithLibwebpBeatsCwebp() {
        #expect(ImageConverter.webpBackend(imageIOCanWrite: false, ffmpeg: ffmpeg, ffmpegEncoders: ["libx264", "libwebp"],
                                           cwebp: cwebp) == .ffmpeg(ffmpeg))
    }

    @Test func homebrewFFmpegWithoutLibwebpFallsBackToCwebp() {
        #expect(ImageConverter.webpBackend(imageIOCanWrite: false, ffmpeg: ffmpeg, ffmpegEncoders: ["libx264", "aac"],
                                           cwebp: cwebp) == .cwebp(cwebp))
        #expect(ImageConverter.webpBackend(imageIOCanWrite: false, ffmpeg: nil, ffmpegEncoders: nil,
                                           cwebp: cwebp) == .cwebp(cwebp))
    }

    @Test func unknownEncoderListPrefersCwebpThenTriesFFmpeg() {
        #expect(ImageConverter.webpBackend(imageIOCanWrite: false, ffmpeg: ffmpeg, ffmpegEncoders: nil,
                                           cwebp: cwebp) == .cwebp(cwebp))
        #expect(ImageConverter.webpBackend(imageIOCanWrite: false, ffmpeg: ffmpeg, ffmpegEncoders: nil,
                                           cwebp: nil) == .ffmpeg(ffmpeg))
    }

    @Test func nothingWhenNoWriterExists() {
        #expect(ImageConverter.webpBackend(imageIOCanWrite: false, ffmpeg: ffmpeg, ffmpegEncoders: ["libx264"],
                                           cwebp: nil) == nil)
        #expect(ImageConverter.webpBackend(imageIOCanWrite: false, ffmpeg: nil, ffmpegEncoders: nil,
                                           cwebp: nil) == nil)
    }
}

/// Real image to WebP conversions through `Converter.convert`. Needs `cwebp` (Homebrew `webp`),
/// which CI doesn't have; run locally with `./scripts/test.sh`.
@Suite(.enabled(if: ToolLocator.find("cwebp") != nil, "needs Homebrew webp (cwebp)"))
struct WebPConversionTests {
    /// The written file's type and size as ImageIO reads it back.
    static func read(_ url: URL) -> (type: String?, width: Int?, height: Int?) {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return (nil, nil, nil) }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        return (CGImageSourceGetType(src) as String?,
                props?[kCGImagePropertyPixelWidth] as? Int, props?[kCGImagePropertyPixelHeight] as? Int)
    }

    /// `file` names the container independently of ImageIO.
    static func fileDescription(_ url: URL) async throws -> String {
        try await ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/file"), ["-b", url.path])
    }

    @Test(arguments: Quality.allCases)
    func pngToWebP(quality: Quality) async throws {
        let dir = try TempDir()
        let input = try dir.png("red.png", width: 40, height: 30)

        let outputs = try await Converter.convert(input, to: format("webp"), options: .init(quality: quality)) { _ in }
        let output = try #require(outputs.first)
        #expect(outputs.count == 1)
        #expect(output.lastPathComponent == "red.webp")
        #expect(try dir.listing() == ["red.png", "red.webp"], "original kept, no temp left behind")

        #expect(try await Self.fileDescription(output).contains("Web/P"))
        let (type, width, height) = Self.read(output)
        #expect(type == UTType.webP.identifier)
        #expect(width == 40)
        #expect(height == 30)
    }

    @Test func neverOverwritesAnExistingWebP() async throws {
        let dir = try TempDir()
        let input = try dir.png("red.png")
        try dir.touch("red.webp", contents: "keep me")

        let output = try await ImageConverter.convert(input, to: format("webp"), quality: .balanced)
        #expect(output.lastPathComponent == "red 2.webp")
        #expect(try String(contentsOf: dir.file("red.webp"), encoding: .utf8) == "keep me")
        #expect(Self.read(output).type == UTType.webP.identifier)
    }

    @Test(.enabled(if: (CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []).contains(UTType.heic.identifier),
                   "this Mac can't write HEIC"))
    func heicToWebP() async throws {
        let dir = try TempDir()
        let png = try dir.png("photo.png", width: 64, height: 48)
        let heic = try await ImageConverter.convert(png, to: format("heic"), quality: .high)
        #expect(heic.lastPathComponent == "photo.heic")

        let output = try await ImageConverter.convert(heic, to: format("webp"), quality: .balanced)
        #expect(output.lastPathComponent == "photo.webp")
        let (type, width, height) = Self.read(output)
        #expect(type == UTType.webP.identifier)
        #expect(width == 64)
        #expect(height == 48)
    }
}
