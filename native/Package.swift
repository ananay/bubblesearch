// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "bubblesearch",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .executableTarget(
            name: "bubblesearch",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/BubbleSearch",
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                // find the embedded Sparkle.framework inside BubbleSearch.app
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
        .testTarget(
            name: "BubbleSearchTests",
            dependencies: ["bubblesearch"],
            path: "Tests/BubbleSearchTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
