// swift-tools-version:6.0
// The recipe manager's portable targets. Everything here builds and tests
// on Linux in CI; platform code lives in the app targets under App/.
import PackageDescription

let package = Package(
    name: "RecipeKit",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "RecipeCore", targets: ["RecipeCore"]),
        .library(name: "RecipeImport", targets: ["RecipeImport"]),
        .library(name: "RecipeModules", targets: ["RecipeModules"]),
        .executable(name: "recipe-cli", targets: ["recipe-cli"]),
    ],
    dependencies: [
        // GRDB: the SQLite index under the library (FTS5 search). Pinned
        // upstream; the fallback is a thin layer over the system sqlite3 C
        // API if it ever fails on Linux (decision 0004).
        .package(
            url: "https://github.com/groue/GRDB.swift.git",
            from: "7.0.0"),
        .package(
            url: "https://github.com/apple/swift-crypto.git",
            from: "3.0.0"),
        .package(
            url: "https://github.com/apple/swift-argument-parser.git",
            from: "1.5.0"),
        .package(
            url: "https://github.com/apple/swift-collections.git",
            from: "1.1.0"),
    ],
    targets: [
        // The system zlib on Linux, which RawDeflate reaches when Apple's
        // Compression framework is unavailable. On Apple platforms the
        // target is unused; declaring it keeps the conditional imports
        // simple.
        .systemLibrary(
            name: "CZlib",
            pkgConfig: "zlib",
            providers: [.apt(["zlib1g-dev"])]),
        .target(name: "RecipeCore", dependencies: [
            .product(name: "GRDB", package: "GRDB.swift"),
            .product(name: "Crypto", package: "swift-crypto"),
            .product(name: "Collections", package: "swift-collections"),
            "RecipeZip",
        ]),
        .target(name: "RecipeImport", dependencies: ["RecipeCore"]),
        .target(name: "RecipeZip", dependencies: ["CZlib"]),
        .target(name: "RecipeModules", dependencies: [
            "RecipeCore",
            "RecipeZip",
            .product(name: "Crypto", package: "swift-crypto"),
        ], resources: [
            .copy("Resources/Schemas")
        ]),
        .executableTarget(
            name: "recipe-cli",
            dependencies: [
                "RecipeCore",
                "RecipeImport",
                "RecipeModules",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]),
        .testTarget(name: "RecipeCoreTests", dependencies: ["RecipeCore"]),
        .testTarget(name: "RecipeImportTests", dependencies: ["RecipeImport"]),
        .testTarget(name: "RecipeModulesTests", dependencies: ["RecipeModules"]),
    ]
)
