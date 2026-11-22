// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Prune",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.1")
    ],
    targets: [
        .executableTarget(
            name: "Prune",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources",
            sources: ["Prune", "PruneCore"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            // Sparkle.framework sits next to the binary in .build and in Contents/Frameworks inside the app.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path",
                                           "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        )
    ]
)
