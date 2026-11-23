// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CheckLet",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "CheckLet",
            path: "Sources/CheckLet",
            linkerSettings: [
                // Apple Intelligence 框架只在 macOS 26+ 存在：弱链接，旧系统上照常启动
                .unsafeFlags(["-Xlinker", "-weak_framework", "-Xlinker", "FoundationModels"]),
            ]
        )
    ]
)
