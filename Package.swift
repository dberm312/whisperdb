// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WhisperDB",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "WhisperDBKit", targets: ["WhisperDBKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/soffes/HotKey.git", from: "0.2.0"),
    ],
    targets: [
        .target(
            name: "WhisperDBKit",
            path: "WhisperDBKit"
        ),
        .executableTarget(
            name: "WhisperDB",
            dependencies: ["WhisperDBKit", "HotKey"],
            path: "WhisperDB",
            exclude: ["Info.plist"],
            resources: [.copy("Resources")]
        ),
    ]
)
