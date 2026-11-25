import Foundation
import Testing
@testable import Convert

/// Real ffmpeg conversions through `Converter.convert`, the same entry point the app uses.
/// Skipped when ffmpeg isn't installed (CI has none); run locally with `./scripts/test.sh`.
@Suite(.enabled(if: ToolLocator.find("ffmpeg") != nil, "needs Homebrew ffmpeg"))
struct VideoConversionTests {
    struct Probe {
        let formatName: String
        let duration: Double
        let video: [String: Any]?
        let audio: [String: Any]?
        var videoCodec: String? { video?["codec_name"] as? String }
        var audioCodec: String? { audio?["codec_name"] as? String }
    }

    static let clipSeconds = 2.0

    /// A 2 s 320x240 H.264 + AAC clip with a test pattern and a tone.
    static func makeClip(in dir: TempDir, name: String = "clip.mov", seconds: Double = clipSeconds,
                         size: String = "320x240") async throws -> URL {
        let ffmpeg = try #require(ToolLocator.find("ffmpeg"))
        let url = dir.file(name)
        try await ProcessRunner.run(ffmpeg, [
            "-hide_banner", "-nostdin", "-y",
            "-f", "lavfi", "-i", "testsrc=size=\(size):rate=25:duration=\(seconds)",
            "-f", "lavfi", "-i", "sine=frequency=440:duration=\(seconds)",
            "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", "-shortest", url.path,
        ])
        return url
    }

    static func probe(_ url: URL) async throws -> Probe {
        let ffmpeg = try #require(ToolLocator.find("ffmpeg"))
        let ffprobe = ffmpeg.deletingLastPathComponent().appendingPathComponent("ffprobe")
        let out = try await ProcessRunner.run(ffprobe, ["-v", "error", "-print_format", "json",
                                                        "-show_format", "-show_streams", url.path])
        let json = try #require(try JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any])
        let format = json["format"] as? [String: Any] ?? [:]
        let streams = json["streams"] as? [[String: Any]] ?? []
        return Probe(formatName: format["format_name"] as? String ?? "",
                     duration: Double(format["duration"] as? String ?? "") ?? 0,
                     video: streams.first { $0["codec_type"] as? String == "video" },
                     audio: streams.first { $0["codec_type"] as? String == "audio" })
    }

    /// Converts and checks the invariants every conversion must keep.
    static func convert(_ input: URL, to id: String, in dir: TempDir) async throws -> (URL, [Double]) {
        let before = try dir.listing()
        let progress = Box<Double>()
        let outputs = try await Converter.convert(input, to: format(id), options: .init()) { progress.append($0) }
        let output = try #require(outputs.first)
        #expect(outputs.count == 1)
        #expect(output.deletingLastPathComponent() == dir.url)
        #expect(output.pathExtension == format(id).ext)
        #expect(FileManager.default.fileExists(atPath: input.path), "original must stay")
        let after = try dir.listing()
        #expect(!after.contains { $0.hasPrefix(".convert-") }, "temp file left behind")
        #expect(Set(after).subtracting(before) == [output.lastPathComponent])
        return (output, progress.values)
    }

    // MARK: - Video outputs

    @Test(arguments: [
        // id, container (substring of ffprobe format_name), video codec, audio codec (nil = none)
        ("mp4", "mp4", "h264", "aac"),
        ("mp4-hevc", "mp4", "hevc", "aac"),
        ("mov", "mov", "h264", "aac"),
        ("m4v", "mp4", "h264", "aac"),
        ("mkv", "matroska", "h264", "aac"),
        ("webm", "webm", "vp9", "opus"),
        ("avi", "avi", "mpeg4", "mp3"),
        ("wmv", "asf", "wmv2", "wmav2"),
        ("gif-anim", "gif", "gif", nil),
    ] as [(String, String, String, String?)])
    func videoToVideo(id: String, container: String, videoCodec: String, audioCodec: String?) async throws {
        let dir = try TempDir()
        let clip = try await Self.makeClip(in: dir)
        let (output, progress) = try await Self.convert(clip, to: id, in: dir)

        let p = try await Self.probe(output)
        #expect(p.formatName.contains(container), "\(id): format \(p.formatName)")
        #expect(p.videoCodec == videoCodec, "\(id): video \(p.videoCodec ?? "none")")
        #expect(p.audioCodec == audioCodec, "\(id): audio \(p.audioCodec ?? "none")")
        if id != "gif-anim" {  // GIF durations are frame-delay based and rounded
            #expect(abs(p.duration - Self.clipSeconds) < 0.3, "\(id): duration \(p.duration)")
        }
        #expect(progress.last == 1)
        #expect(progress.allSatisfy { (0...1).contains($0) })
    }

    @Test func hevcIsTaggedForApplePlayers() async throws {
        let dir = try TempDir()
        let (output, _) = try await Self.convert(try await Self.makeClip(in: dir), to: "mp4-hevc", in: dir)
        // QuickTime and Finder previews only play HEVC in MP4 when tagged hvc1, not hev1.
        #expect(try await Self.probe(output).video?["codec_tag_string"] as? String == "hvc1")
    }

    @Test func gifKeepsWidthAndLoops() async throws {
        let dir = try TempDir()
        let (output, _) = try await Self.convert(try await Self.makeClip(in: dir), to: "gif-anim", in: dir)
        let p = try await Self.probe(output)
        #expect(p.video?["width"] as? Int == 320, "smaller than the 640 cap, so width is kept")
        let data = try Data(contentsOf: output)
        #expect(data.range(of: Data("NETSCAPE2.0".utf8)) != nil, "loop extension missing")
    }

    @Test func gifIsScaledDownToTheQualityCap() async throws {
        let dir = try TempDir()
        let clip = try await Self.makeClip(in: dir, size: "1280x720")
        let (output, _) = try await Self.convert(clip, to: "gif-anim", in: dir)
        let p = try await Self.probe(output)
        #expect(p.video?["width"] as? Int == 640)
        #expect(p.video?["height"] as? Int == 360)
    }

    // MARK: - Video to audio

    @Test(arguments: [
        ("mp3", "mp3"), ("m4a", "aac"), ("wav", "pcm_s16le"), ("aiff", "pcm_s16be"), ("flac", "flac"),
        ("alac", "alac"), ("ogg", "vorbis"), ("opus", "opus"), ("wma", "wmav2"), ("ac3", "ac3"),
    ])
    func videoToAudio(id: String, audioCodec: String) async throws {
        let dir = try TempDir()
        let clip = try await Self.makeClip(in: dir)
        let (output, _) = try await Self.convert(clip, to: id, in: dir)

        let p = try await Self.probe(output)
        #expect(p.audioCodec == audioCodec, "\(id): audio \(p.audioCodec ?? "none")")
        #expect(p.video == nil, "\(id): video stream should be dropped")
        #expect(abs(p.duration - Self.clipSeconds) < 0.3, "\(id): duration \(p.duration)")
    }

    // MARK: - Safety

    @Test func neverOverwritesAnEarlierOutput() async throws {
        let dir = try TempDir()
        let clip = try await Self.makeClip(in: dir)
        let (first, _) = try await Self.convert(clip, to: "mp4", in: dir)
        let (second, _) = try await Self.convert(clip, to: "mp4", in: dir)
        #expect(first.lastPathComponent == "clip.mp4")
        #expect(second.lastPathComponent == "clip 2.mp4")
    }

    @Test func stoppingMidConversionLeavesNothingBehind() async throws {
        let dir = try TempDir()
        // Long enough that VP9 is still encoding when we cancel.
        let clip = try await Self.makeClip(in: dir, seconds: 60, size: "1280x720")
        let progress = Box<Double>()
        let task = Task {
            try await Converter.convert(clip, to: format("webm"), options: .init()) { progress.append($0) }
        }
        // Wait for ffmpeg to report some progress, so it's really mid-encode.
        for _ in 0..<200 where progress.values.isEmpty { try await Task.sleep(for: .milliseconds(50)) }
        #expect(!progress.values.isEmpty, "ffmpeg never reported progress")
        task.cancel()

        await #expect(throws: CancellationError.self) { _ = try await task.value }
        #expect(try dir.listing() == ["clip.mov"], "partial output or temp file left behind")
    }

    @Test func corruptInputFailsWithFFmpegsMessage() async throws {
        let dir = try TempDir()
        let bogus = try dir.touch("broken.mp4", contents: "this is not a video")
        do {
            _ = try await Converter.convert(bogus, to: format("mov"), options: .init()) { _ in }
            Issue.record("Expected an error")
        } catch let ConvertError.toolFailed(detail) {
            #expect(!detail.isEmpty)
        }
        #expect(try dir.listing() == ["broken.mp4"])
    }
}
