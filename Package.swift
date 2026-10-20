// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Wineup",
    platforms: [.macOS(.v14)],
    dependencies: [
        // MIT. Decoders de FLAC/MP3/Ogg/Opus/APE/DSD etc., leitura de tags e ReplayGain.
        .package(url: "https://github.com/sbooth/SFBAudioEngine", from: "0.14.0"),
    ],
    targets: [
        .executableTarget(
            name: "Wineup",
            dependencies: [
                "WineupCore",
                .product(name: "SFBAudioEngine", package: "SFBAudioEngine"),
            ],
            path: "Sources/Wineup"
        ),
        // Núcleo puro (Foundation apenas): contratos e lógica testável sem UI.
        .target(
            name: "WineupCore",
            path: "Sources/WineupCore",
            swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]
        ),
        .testTarget(
            name: "WineupCoreTests",
            dependencies: ["WineupCore"],
            path: "Tests/WineupCoreTests"
        )
    ]
)
