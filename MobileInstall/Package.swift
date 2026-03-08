// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MobileInstall",
    platforms: [.macOS(.v11)],
    products: [
        .executable(name: "MobileInstall", targets: ["MobileInstall"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Lakr233/AppleMobileDeviceLibrary.git", from: "1.0.0"),
        .package(url: "https://github.com/Lakr233/libzip-spm.git", from: "1.11.3"),
    ],
    targets: [
        .executableTarget(
            name: "MobileInstall",
            dependencies: [
                "MobileInstallEndianness",
                "AppleMobileDeviceLibrary",
                .product(name: "zip", package: "libzip-spm"),
            ],
            cSettings: [
                .unsafeFlags(["-w"]),
                .define("PACKAGE_NAME=\"MobileInstall\""),
                .define("PACKAGE_VERSION=\"1762d5f1\""),
                .define("PACKAGE_URL=\"UNAVAILABLE\""),
                .define("PACKAGE_BUGREPORT=\"UNAVAILABLE\""),
                .define("HAVE_VASPRINTF"),
                .define("HAVE_ASPRINTF"),
            ],
            linkerSettings: [
                .linkedLibrary("z"),
                .linkedLibrary("lzma"),
            ]
        ),
        .target(name: "MobileInstallEndianness"),
    ]
)
