// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "AiAndo",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "AiAndo",
            path: "Sources/AiAndo",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "AiAndoTests",
            dependencies: ["AiAndo"],
            path: "Tests/AiAndoTests"
        ),
    ]
)
