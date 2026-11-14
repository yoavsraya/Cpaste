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
    ],
    targets: [
        .target(name: "CpasteCore", dependencies: [.product(name: "GRDB", package: "GRDB.swift")]),
        .executableTarget(name: "Cpaste", dependencies: ["CpasteCore"]),
        .testTarget(name: "CpasteCoreTests", dependencies: ["CpasteCore"]),
        .testTarget(name: "CpasteTests", dependencies: ["Cpaste"]),
    ]
)
