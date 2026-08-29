// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NotebarCore",
    // Deliberately lower than the app's macOS 26 floor: this package has no UI
    // dependency, and keeping its floor low keeps it portable (spec section 3, rule 1).
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "NotebarCore", targets: ["NotebarCore"]),
        .library(name: "NotebarStore", targets: ["NotebarStore"]),
    ],
    dependencies: [
        // Only ever a dependency of NotebarStore, never of NotebarCore itself
        // — see that target below and scripts/check-core-purity.sh, which
        // fails the build if this ever migrates onto the NotebarCore target.
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "NotebarCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "NotebarStore",
            dependencies: [
                "NotebarCore",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "NotebarCoreTests",
            dependencies: ["NotebarCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "NotebarStoreTests",
            dependencies: ["NotebarStore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
