// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CheckLet",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "CheckLet",
            path: "Sources/CheckLet"
        )
    ]
)
