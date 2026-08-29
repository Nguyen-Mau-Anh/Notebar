// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NotebarCore",
    // Deliberately lower than the app's macOS 26 floor: this package has no UI
    // dependency, and keeping its floor low keeps it portable (spec section 3, rule 1).
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "NotebarCore", targets: ["NotebarCore"])
    ],
    targets: [
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
)
