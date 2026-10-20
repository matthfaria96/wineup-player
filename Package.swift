// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Wineup",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "wineup-audiocheck", targets: ["WineupAudioCheck"]),
    ],
    dependencies: [
        // MIT. Decoders de FLAC/MP3/Ogg/Opus/APE/DSD etc., leitura de tags e ReplayGain.
        .package(url: "https://github.com/sbooth/SFBAudioEngine", from: "0.14.0"),
        // MIT. SQLite: migrations, FTS5, DatabasePool (WAL).
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
        // TagLib (LGPL/MPL) já resolvido pelo SFBAudioEngine; usado direto pelo shim WineupID3.
        .package(url: "https://github.com/sbooth/CXXTagLib", from: "2.3.2"),
    ],
    targets: [
        .executableTarget(
            name: "Wineup",
            dependencies: [
                "WineupCore",
                "WineupLibrary",
                "WineupAudio",
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
        // Shim ObjC++ mínimo sobre TagLib (API C).
        .target(
            name: "WineupID3",
            dependencies: [.product(name: "taglib", package: "CXXTagLib")],
            path: "Sources/WineupID3"
        ),
        // Banco SQLite, varredura e escrita segura.
        .target(
            name: "WineupLibrary",
            dependencies: [
                "WineupCore",
                "WineupID3",
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "SFBAudioEngine", package: "SFBAudioEngine"),
            ],
            path: "Sources/WineupLibrary",
            swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]
        ),
        // Cadeia de efeitos (velocidade, EQ, balanço/ganho) e medidor sobre AVAudioEngine.
        .target(
            name: "WineupAudio",
            dependencies: [
                "WineupCore",
                .product(name: "SFBAudioEngine", package: "SFBAudioEngine"),
            ],
            path: "Sources/WineupAudio",
            swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]
        ),
        // Verificação offline do caminho SFB real (release; render manual, sem som).
        .executableTarget(
            name: "WineupAudioCheck",
            dependencies: [
                "WineupAudio",
                "WineupCore",
                .product(name: "SFBAudioEngine", package: "SFBAudioEngine"),
            ],
            path: "Sources/WineupAudioCheck"
        ),
        .testTarget(
            name: "WineupAudioTests",
            dependencies: [
                "WineupAudio",
                "WineupCore",
                .product(name: "SFBAudioEngine", package: "SFBAudioEngine"),
            ],
            path: "Tests/WineupAudioTests"
        ),
        .testTarget(
            name: "WineupLibraryTests",
            dependencies: [
                "WineupLibrary",
                "WineupID3",
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "SFBAudioEngine", package: "SFBAudioEngine"),
            ],
            path: "Tests/WineupLibraryTests"
        ),
        .testTarget(
            name: "WineupCoreTests",
            dependencies: ["WineupCore"],
            path: "Tests/WineupCoreTests"
        )
    ]
)
