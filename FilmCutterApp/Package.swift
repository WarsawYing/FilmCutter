// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FilmCutterApp",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "FilmCutterApp",
            path: "Sources",
            resources: [
                .copy("Resources/logo.svg")
            ]
        )
    ]
)
