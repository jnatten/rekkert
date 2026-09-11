// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RekkertKit",
    platforms: [.iOS(.v26), .watchOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "RekkertCore", targets: ["RekkertCore"]),
        .library(name: "RekkertSync", targets: ["RekkertSync"]),
    ],
    targets: [
        .target(
            name: "RekkertCore",
            swiftSettings: [.swiftLanguageMode(.v6), .defaultIsolation(nil)]
        ),
        .target(
            name: "RekkertSync",
            dependencies: ["RekkertCore"],
            swiftSettings: [.swiftLanguageMode(.v6), .defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "RekkertCoreTests",
            dependencies: ["RekkertCore"],
            swiftSettings: [.swiftLanguageMode(.v6), .defaultIsolation(nil)]
        ),
        .testTarget(
            name: "RekkertSyncTests",
            dependencies: ["RekkertSync"],
            swiftSettings: [.swiftLanguageMode(.v6), .defaultIsolation(MainActor.self)]
        ),
    ]
)
