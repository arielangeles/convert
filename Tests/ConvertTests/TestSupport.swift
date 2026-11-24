import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import Convert

/// A fresh directory under the system temp dir, removed when the value is released.
final class TempDir {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConvertTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    func file(_ name: String) -> URL { url.appendingPathComponent(name) }

    @discardableResult
    func touch(_ name: String, contents: String = "x") throws -> URL {
        let f = file(name)
        try FileManager.default.createDirectory(at: f.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: f, atomically: true, encoding: .utf8)
        return f
    }

    /// Names of everything in the directory, hidden files included, sorted.
    func listing() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: url.path).sorted()
    }

    /// Writes a small solid-colour PNG.
    @discardableResult
    func png(_ name: String, width: Int = 4, height: Int = 3) throws -> URL {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = ctx.makeImage()!
        let f = file(name)
        let dest = CGImageDestinationCreateWithURL(f as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
        return f
    }
}

func format(_ id: String) -> OutputFormat {
    guard let f = FormatCatalog.all.first(where: { $0.id == id }) else { fatalError("No format \(id)") }
    return f
}

/// Collects values from @Sendable callbacks.
final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [T] = []
    func append(_ item: T) { lock.lock(); items.append(item); lock.unlock() }
    var values: [T] { lock.lock(); defer { lock.unlock() }; return items }
}
