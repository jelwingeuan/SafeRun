// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SafeRun",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "SafeRun",
            path: "Sources/SafeRun",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "SafeRunTests",
            dependencies: ["SafeRun"],
            path: "Tests/SafeRunTests"
        )
    ]
)
