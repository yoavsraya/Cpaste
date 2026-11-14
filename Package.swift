// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Cpaste",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CpasteCore", targets: ["CpasteCore"]),
        .executable(name: "Cpaste", targets: ["Cpaste"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        // In-app updates: a signed feed of releases and a one-click installer.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.4"),
    ],
    targets: [
        .target(name: "CpasteCore", dependencies: [.product(name: "GRDB", package: "GRDB.swift")]),
        .executableTarget(name: "Cpaste", dependencies: ["CpasteCore", .product(name: "Sparkle", package: "Sparkle")]),
        .testTarget(name: "CpasteCoreTests", dependencies: ["CpasteCore"]),
        .testTarget(name: "CpasteTests", dependencies: ["Cpaste"]),
    ]
)
