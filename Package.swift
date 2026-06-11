// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "SwiftBorder",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "SwiftBorder",
            path: "Sources/SwiftBorder",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
