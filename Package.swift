// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Convert",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Convert",
            path: "Sources/Convert"
        ),
        // Swift Testing (not XCTest): it ships with Command Line Tools, XCTest needs full Xcode.
        .testTarget(
            name: "ConvertTests",
            dependencies: ["Convert"],
            path: "Tests/ConvertTests"
        ),
    ]
)
