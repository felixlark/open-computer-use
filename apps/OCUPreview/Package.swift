// swift-tools-version: 6.2
import PackageDescription

// The observer builds/tests independently of the automation provider.
let package = Package(
    name: "OCUPreview",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "OCUPreview", targets: ["OCUPreview"])],
    targets: [
        .executableTarget(name: "OCUPreview", path: "Sources"),
        .testTarget(name: "OCUPreviewTests", dependencies: ["OCUPreview"], path: "Tests"),
    ]
)
