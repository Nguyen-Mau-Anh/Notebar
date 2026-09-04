// swift-tools-version: 6.0
import PackageDescription

// Package.swift is Swift, evaluated by the build machine's own toolchain
// before any target is compiled — so this `#if` runs at manifest time, not
// at Swift-source-compile time. `canImport(Darwin)` is true only on Apple
// platforms (macOS/iOS/tvOS/watchOS/visionOS): Linux uses Glibc, Windows uses
// WinSDK/ucrt, so this is the same idiom SwiftPM itself and many cross-
// platform packages use to gate Apple-only targets, and it stays correct
// automatically if Apple ships another platform later — `#if os(macOS)`
// would not, and would also wrongly exclude iOS/etc. if this package ever
// grew to support them.
//
// NotebarStore depends on GRDB (Apple platforms + Linux, not Windows) and on
// AppKit directly (for RTF encoding — see scripts/check-core-purity.sh), so
// it and its test target, its product, and the GRDB dependency itself only
// exist in the manifest on Apple platforms. NotebarCore has zero platform-
// specific dependencies and is declared unconditionally so a Windows build
// sees exactly `NotebarCore` + `NotebarCoreTests`.
var targets: [Target] = [
    .target(
        name: "NotebarCore",
        swiftSettings: [.swiftLanguageMode(.v5)]
    ),
    .testTarget(
        name: "NotebarCoreTests",
        dependencies: ["NotebarCore"],
        swiftSettings: [.swiftLanguageMode(.v5)]
    ),
]

var products: [Product] = [
    .library(name: "NotebarCore", targets: ["NotebarCore"]),
]

var dependencies: [Package.Dependency] = []

#if canImport(Darwin)
products.append(.library(name: "NotebarStore", targets: ["NotebarStore"]))

dependencies.append(
    // Only ever a dependency of NotebarStore, never of NotebarCore itself
    // — see that target below and scripts/check-core-purity.sh, which
    // fails the build if this ever migrates onto the NotebarCore target.
    .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0")
)

targets.append(contentsOf: [
    .target(
        name: "NotebarStore",
        dependencies: [
            "NotebarCore",
            .product(name: "GRDB", package: "GRDB.swift"),
        ],
        swiftSettings: [.swiftLanguageMode(.v5)]
    ),
    .testTarget(
        name: "NotebarStoreTests",
        dependencies: ["NotebarStore"],
        swiftSettings: [.swiftLanguageMode(.v5)]
    ),
])
#endif

let package = Package(
    name: "NotebarCore",
    // Deliberately lower than the app's macOS 26 floor: this package has no UI
    // dependency, and keeping its floor low keeps it portable (spec section 3, rule 1).
    // This is a floor for macOS only — it does not exclude other platforms; SwiftPM
    // packages with no `platforms:` entry for a given OS build there using that
    // toolchain's own defaults, which is exactly what makes the Darwin-gated
    // NotebarCore-only manifest above buildable on Linux/Windows at all.
    platforms: [.macOS(.v14)],
    products: products,
    dependencies: dependencies,
    targets: targets
)
