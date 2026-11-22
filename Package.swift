// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Prune",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Prune",
            path: "Sources/Prune",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
