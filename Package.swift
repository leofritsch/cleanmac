// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "CleanMac",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "CleanMac",
            path: "Sources/CleanMac"
        )
    ]
)
