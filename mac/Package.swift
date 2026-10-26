// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "GimmeRemote",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "GimmeRemote", targets: ["GimmeRemote"]),
        .executable(name: "gimme", targets: ["GimmeCLI"]),
        .library(name: "RemoteCore", targets: ["RemoteCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.24.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird-websocket.git", from: "2.8.1"),
    ],
    targets: [
        .target(name: "RemoteCore"),
        .target(name: "RemoteTransport", dependencies: [
            "RemoteCore",
            .product(name: "Hummingbird", package: "hummingbird"),
            .product(name: "HummingbirdWebSocket", package: "hummingbird-websocket"),
        ]),
        .executableTarget(name: "GimmeRemote", dependencies: ["RemoteCore", "RemoteTransport"]),
        .executableTarget(name: "GimmeCLI", dependencies: ["RemoteCore"]),
        .executableTarget(name: "TransportChecks", dependencies: ["RemoteCore", "RemoteTransport"], path: "Checks"),
        .testTarget(name: "RemoteCoreTests", dependencies: ["RemoteCore"]),
    ]
)
