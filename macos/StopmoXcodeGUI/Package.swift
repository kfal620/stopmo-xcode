// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StopmoXcodeGUI",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "StopmoXcodeGUI", targets: ["StopmoXcodeGUI"])
    ],
    targets: [
        .executableTarget(
            name: "StopmoXcodeGUI",
            path: "Sources/StopmoXcodeGUI"
        ),
        .testTarget(
            name: "StopmoXcodeGUITests",
            dependencies: ["StopmoXcodeGUI"],
            path: "Tests/StopmoXcodeGUITests"
        )
    ]
)
