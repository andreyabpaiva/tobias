// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "tobias",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Tobias", targets: ["Tobias"]),
        .library(name: "TobiasCore", targets: ["TobiasCore"]),
    ],
    targets: [
        .target(
            name: "TobiasCore",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "Tobias",
            dependencies: ["TobiasCore"],
            resources: [.copy("Resources/Fonts")]
        ),
        .testTarget(
            name: "TobiasCoreTests",
            dependencies: ["TobiasCore"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
