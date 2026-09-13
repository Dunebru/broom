// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Broom",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Broom",
            path: "Sources/Broom",
            swiftSettings: [.unsafeFlags(["-Ounchecked"], .when(configuration: .release))]
        ),
        .testTarget(name: "BroomTests", dependencies: ["Broom"], path: "Tests/BroomTests"),
    ]
)
