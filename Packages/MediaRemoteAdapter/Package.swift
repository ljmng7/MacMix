// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "MediaRemoteAdapter",
    platforms: [
        .macOS(.v10_15)
    ],
    products: [
        .library(
            name: "MediaRemoteAdapter",
            type: .dynamic,
            targets: ["MediaRemoteAdapter"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "MediaRemoteAdapter",
            dependencies: ["CIMediaRemote"],
            resources: [
                .copy("Resources/run.pl"),
                .copy("Resources/MediaRemoteAdapter-LICENSE.txt")
            ]
        ),
        .target(
            name: "CIMediaRemote",
            dependencies: [],
            publicHeadersPath: "include",
            cSettings: [
                .unsafeFlags(["-fobjc-arc"])
            ],
            linkerSettings: [
                .unsafeFlags(["-framework", "Foundation"]),
                .unsafeFlags(["-framework", "AppKit"])
            ]
        )
    ]
) 
