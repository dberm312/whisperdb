// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WhisperDB",
    // macOS 15 is required by grpc-swift v2 (used only by the macOS-only ParakeetKit
    // target). iOS stays at 16 — the iOS app does not link ParakeetKit/gRPC.
    platforms: [.macOS("15.0"), .iOS(.v16)],
    products: [
        .library(name: "WhisperDBKit", targets: ["WhisperDBKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/soffes/HotKey.git", from: "0.2.0"),
        .package(url: "https://github.com/grpc/grpc-swift.git", from: "2.0.0"),
        .package(url: "https://github.com/grpc/grpc-swift-nio-transport.git", from: "1.0.0"),
        .package(url: "https://github.com/grpc/grpc-swift-protobuf.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.28.0"),
    ],
    targets: [
        .target(
            name: "WhisperDBKit",
            path: "WhisperDBKit"
        ),
        // macOS-only: NVIDIA Parakeet streaming ASR over gRPC (NVIDIA Riva).
        .target(
            name: "ParakeetKit",
            dependencies: [
                "WhisperDBKit",
                .product(name: "GRPCCore", package: "grpc-swift"),
                .product(name: "GRPCNIOTransportHTTP2", package: "grpc-swift-nio-transport"),
                .product(name: "GRPCProtobuf", package: "grpc-swift-protobuf"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ],
            path: "ParakeetKit",
            exclude: ["Riva/protos"]
        ),
        .executableTarget(
            name: "WhisperDB",
            dependencies: ["WhisperDBKit", "ParakeetKit", "HotKey"],
            path: "WhisperDB",
            exclude: ["Info.plist"],
            resources: [.copy("Resources")]
        ),
    ]
)
