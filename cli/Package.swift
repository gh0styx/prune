// swift-tools-version:5.9
import PackageDescription

// The CLI compiles the same AppKit-free sources as Prune.app (../Sources/PruneCore) through symlinks in
// Sources/prune/core, so both share scanners, categories and the Trash safety rules.
let package = Package(
    name: "prune",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "prune", targets: ["prune"])],
    targets: [
        .executableTarget(name: "prune", path: "Sources/prune")
    ]
)
