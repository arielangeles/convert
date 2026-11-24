import Foundation
import Testing
@testable import Convert

@Suite struct MediaClassifierTests {
    @Test(arguments: [
        ("song.mp3", MediaKind.audio), ("SONG.MP3", .audio), ("voice.opus", .audio), ("track.flac", .audio),
        ("clip.mkv", .video), ("clip.MOV", .video), ("clip.webm", .video),
        ("photo.heic", .image), ("photo.jpg", .image), ("photo.png", .image), ("photo.webp", .image),
        ("notes.md", .document), ("letter.docx", .document), ("page.html", .document),
        ("paper.pdf", .pdf), ("PAPER.PDF", .pdf),
    ])
    func classifiesByExtension(name: String, expected: MediaKind) {
        #expect(MediaClassifier.kind(of: URL(fileURLWithPath: "/tmp/\(name)")) == expected)
    }

    @Test(arguments: ["archive.zip", "binary.dylib", "noextension"])
    func unknownFilesAreSkipped(name: String) {
        #expect(MediaClassifier.kind(of: URL(fileURLWithPath: "/tmp/\(name)")) == nil)
    }

    @Test func expandsFoldersRecursivelyAndSkipsHiddenAndUnknown() throws {
        let dir = try TempDir()
        try dir.touch("a.mp3")
        try dir.touch("sub/b.png")
        try dir.touch("sub/deeper/c.pdf")
        try dir.touch("sub/notes.zip")
        try dir.touch(".hidden.mp3")
        try dir.touch("sub/.secret/d.mp3")

        let names = MediaClassifier.expand([dir.url]).map(\.lastPathComponent).sorted()
        #expect(names == ["a.mp3", "b.png", "c.pdf"])
    }

    @Test func keepsLooseFilesAndDropsMissingOnes() throws {
        let dir = try TempDir()
        let song = try dir.touch("a.mp3")
        let zip = try dir.touch("b.zip")
        let missing = dir.file("gone.mp3")
        #expect(MediaClassifier.expand([song, zip, missing]) == [song])
    }

    @Test func stopsAtTheLimit() throws {
        let dir = try TempDir()
        for i in 0..<10 { try dir.touch("f\(i).mp3") }
        #expect(MediaClassifier.expand([dir.url], limit: 3).count == 3)
    }
}
