// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Convert",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Convert",
            path: "Sources/Convert"
        )
    ]
)
