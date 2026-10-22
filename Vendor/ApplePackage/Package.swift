// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ApplePackage",
    platforms: [
        .iOS(.v15),
        .macCatalyst(.v15),
        .macOS(.v11),
        .tvOS(.v15),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "ApplePackage", targets: ["ApplePackage"]),
        .executable(name: "ApplePackageTool", targets: ["ApplePackageTool"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Lakr233/openssl-spm.git", from: "3.6.2"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", .upToNextMajor(from: "0.9.0")),
        .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.9.0"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.2.1"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
    ],
    targets: [
        .target(name: "CApplePackage", publicHeadersPath: "include"),
        .executableTarget(
            name: "ApplePackageTool",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .target(name: "ApplePackage"),
            ],
        ),
        .target(
            name: "ApplePackage",
            dependencies: [
                .target(name: "CApplePackage"),
                .product(name: "OpenSSL", package: "openssl-spm"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "Collections", package: "swift-collections"),
                .product(name: "Logging", package: "swift-log"),
            ],
            resources: [.process("SAP/Resources")],
        ),
        .testTarget(name: "ApplePackageTests", dependencies: ["ApplePackage"], resources: [.copy("SAP/Fixtures")]),
        .testTarget(name: "ApplePackageToolTests", dependencies: ["ApplePackageTool"]),
    ],
    swiftLanguageModes: [.v6],
)
