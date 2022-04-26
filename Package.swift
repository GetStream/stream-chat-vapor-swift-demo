// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "StreamVaporBackend",
    platforms: [
       .macOS(.v12)
    ],
    dependencies: [
        // 💧 A server-side Swift web framework.
        .package(url: "https://github.com/vapor/vapor.git", from: "4.0.0"),
        .package(url: "https://github.com/vapor/fluent.git", from: "4.0.0"),
        .package(url: "https://github.com/vapor/fluent-postgres-driver.git", from: "2.0.0"),
        .package(url: "https://github.com/vapor/jwt.git", from: "4.0.0"),
        .package(url: "https://github.com/vapor-community/Imperial.git", from: "1.0.0"),
        .package(name: "StreamChat", url: "https://github.com/GetStream/stream-chat-vapor-swift.git", from: "0.1.0"),
    ],
    targets: [
        .executableTarget(
            name: "StreamVaporBackend",
            dependencies: [
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
                .product(name: "Vapor", package: "vapor"),
                .product(name: "JWT", package: "jwt"),
                .product(name: "ImperialGitHub", package: "Imperial"),
                .product(name: "ImperialGoogle", package: "Imperial"),
                .product(name: "StreamSDKVapor", package: "StreamChat"),
            ],
            swiftSettings: [
                // Enable better optimizations when building in Release configuration. Despite the use of
                // the `.unsafeFlags` construct required by SwiftPM, this flag is recommended for Release
                // builds. See <https://github.com/swift-server/guides/blob/main/docs/building.md#building-for-production> for details.
                .unsafeFlags(["-cross-module-optimization"], .when(configuration: .release))
            ]
        ),
        .testTarget(name: "StreamVaporBackendTests", dependencies: [
            .target(name: "StreamVaporBackend"),
            .product(name: "XCTVapor", package: "vapor"),
        ]),
    ]
)
