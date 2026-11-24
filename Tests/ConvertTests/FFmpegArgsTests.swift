import Testing
@testable import Convert

@Suite struct FFmpegArgsTests {
    /// Adding a format to the catalog without handling it in `codecArgs` would silently
    /// produce ffmpeg's defaults. This catches that.
    @Test(arguments: FormatCatalog.audio + FormatCatalog.video, Quality.allCases)
    func everyAudioAndVideoFormatHasCodecArgs(format: OutputFormat, quality: Quality) {
        #expect(!FFmpeg.codecArgs(for: format, quality: quality).isEmpty)
    }

    @Test(arguments: FormatCatalog.audio)
    func audioOutputsDropVideoStreams(format: OutputFormat) {
        #expect(FFmpeg.codecArgs(for: format, quality: .balanced).first == "-vn")
    }

    @Test func qualityChangesBitrate() {
        func bitrate(_ q: Quality) -> String? {
            let args = FFmpeg.codecArgs(for: format("mp3"), quality: q)
            return args.firstIndex(of: "-b:a").map { args[$0 + 1] }
        }
        #expect(bitrate(.high) == "320k")
        #expect(bitrate(.balanced) == "192k")
        #expect(bitrate(.small) == "128k")
    }

    @Test func hevcUsesHardwareEncoderAndAppleTag() {
        let args = FFmpeg.codecArgs(for: format("mp4-hevc"), quality: .balanced)
        #expect(args.contains("hevc_videotoolbox"))
        #expect(args.contains("hvc1"))
        #expect(args.contains("+faststart"))
    }

    @Test func gifHasNoAudioAndLoops() {
        let args = FFmpeg.codecArgs(for: format("gif-anim"), quality: .balanced)
        #expect(args.contains("-an"))
        #expect(args.last == "0" && args.dropLast().last == "-loop")
    }

    @Test func nonMediaFormatsGetNoArgs() {
        #expect(FFmpeg.codecArgs(for: format("png"), quality: .balanced).isEmpty)
    }
}
