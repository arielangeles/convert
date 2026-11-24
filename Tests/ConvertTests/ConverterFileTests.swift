import Foundation
import Testing
@testable import Convert

/// The "never overwrite" and "atomic write" invariants from CLAUDE.md.
@Suite struct ConverterFileTests {
    struct Boom: Error {}

    @Test func outputGoesNextToInputWithNewExtension() throws {
        let dir = try TempDir()
        let input = try dir.touch("Interview.wav")
        #expect(Converter.uniqueOutputURL(for: input, ext: "mp3") == dir.file("Interview.mp3"))
    }

    @Test func neverOverwritesExistingFiles() throws {
        let dir = try TempDir()
        let input = try dir.touch("Interview.wav")
        try dir.touch("Interview.mp3")
        #expect(Converter.uniqueOutputURL(for: input, ext: "mp3").lastPathComponent == "Interview 2.mp3")
        try dir.touch("Interview 2.mp3")
        #expect(Converter.uniqueOutputURL(for: input, ext: "mp3").lastPathComponent == "Interview 3.mp3")
    }

    @Test func sameExtensionDoesNotClobberTheInput() throws {
        let dir = try TempDir()
        let input = try dir.touch("photo.png")
        #expect(Converter.uniqueOutputURL(for: input, ext: "png").lastPathComponent == "photo 2.png")
    }

    @Test func suffixIsAddedBeforeTheCounter() throws {
        let dir = try TempDir()
        let input = try dir.touch("doc.pdf")
        #expect(Converter.uniqueOutputURL(for: input, ext: "png", suffix: "-p1").lastPathComponent == "doc-p1.png")
        try dir.touch("doc-p1.png")
        #expect(Converter.uniqueOutputURL(for: input, ext: "png", suffix: "-p1").lastPathComponent == "doc-p1 2.png")
    }

    @Test func atomicWriteSyncMovesTempIntoPlace() throws {
        let dir = try TempDir()
        let dest = dir.file("out.txt")
        var tempName = ""
        try Converter.atomicWriteSync(to: dest) { tmp in
            tempName = tmp.lastPathComponent
            #expect(tmp.deletingLastPathComponent() == dir.url)
            try "hello".write(to: tmp, atomically: false, encoding: .utf8)
        }
        #expect(tempName.hasPrefix(".convert-") && tempName.hasSuffix(".txt"))
        #expect(try String(contentsOf: dest, encoding: .utf8) == "hello")
        #expect(try dir.listing() == ["out.txt"])
    }

    @Test func atomicWriteSyncCleansUpOnFailure() throws {
        let dir = try TempDir()
        let dest = dir.file("out.txt")
        #expect(throws: Boom.self) {
            try Converter.atomicWriteSync(to: dest) { tmp in
                try "partial".write(to: tmp, atomically: false, encoding: .utf8)
                throw Boom()
            }
        }
        #expect(try dir.listing().isEmpty)
    }

    @Test func atomicWriteCleansUpOnFailure() async throws {
        let dir = try TempDir()
        let dest = dir.file("out.mp3")
        await #expect(throws: Boom.self) {
            try await Converter.atomicWrite(to: dest) { tmp in
                try "partial".write(to: tmp, atomically: false, encoding: .utf8)
                throw Boom()
            }
        }
        #expect(try dir.listing().isEmpty)
    }

    @Test func atomicWriteCleansUpOnCancellation() async throws {
        let dir = try TempDir()
        let dest = dir.file("out.mp3")
        await #expect(throws: CancellationError.self) {
            try await Converter.atomicWrite(to: dest) { tmp in
                try "partial".write(to: tmp, atomically: false, encoding: .utf8)
                throw CancellationError()
            }
        }
        #expect(try dir.listing().isEmpty)
    }

    @Test func unsupportedConversionThrowsAndLeavesInputAlone() async throws {
        let dir = try TempDir()
        let input = try dir.png("photo.png")
        await #expect(throws: ConvertError.self) {
            _ = try await Converter.convert(input, to: format("mp3"), options: .init()) { _ in }
        }
        #expect(try dir.listing() == ["photo.png"])
    }
}
