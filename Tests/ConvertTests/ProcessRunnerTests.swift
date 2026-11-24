import Foundation
import Testing
@testable import Convert

@Suite struct ProcessRunnerTests {
    let sh = URL(fileURLWithPath: "/bin/sh")

    @Test func returnsStdoutAndStreamsLines() async throws {
        let lines = Box<String>()
        let out = try await ProcessRunner.run(sh, ["-c", "printf 'one\\ntwo\\nthree\\n'"]) { lines.append($0) }
        #expect(out == "one\ntwo\nthree\n")
        #expect(lines.values == ["one", "two", "three"])
    }

    @Test func nonZeroExitThrowsWithStderrTail() async throws {
        do {
            try await ProcessRunner.run(sh, ["-c", "echo first >&2; echo bad input >&2; exit 3"])
            Issue.record("Expected an error")
        } catch let ConvertError.toolFailed(detail) {
            #expect(detail.hasSuffix("bad input"))
        }
    }

    @Test func emptyStderrStillGivesAMessage() async throws {
        do {
            try await ProcessRunner.run(sh, ["-c", "exit 1"])
            Issue.record("Expected an error")
        } catch let ConvertError.toolFailed(detail) {
            #expect(!detail.isEmpty)
        }
    }

    @Test func cancellingTheTaskStopsTheProcess() async throws {
        let start = ContinuousClock.now
        let task = Task { try await ProcessRunner.run(URL(fileURLWithPath: "/bin/sleep"), ["30"]) }
        try await Task.sleep(for: .milliseconds(300))
        task.cancel()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        #expect(ContinuousClock.now - start < .seconds(10))
    }
}
