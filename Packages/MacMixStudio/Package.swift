// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacMixStudio",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "MacMixStudio", targets: ["MacMixStudio"])
    ],
    targets: [
        // Real-time DSP must not run unoptimized while debugging the Swift UI.
        .target(name: "MacMixEQDSP",
                cSettings: [.unsafeFlags(["-O2"], .when(configuration: .debug))],
                linkerSettings: [.linkedFramework("Accelerate")]),
        .target(
            name: "MacMixStudio",
            dependencies: ["MacMixEQDSP"],
            linkerSettings: [
                .linkedFramework("ApplicationServices"),
                .linkedFramework("IOKit")
            ]
        ),
        .testTarget(
            name: "MacMixStudioTests",
            dependencies: ["MacMixStudio"]
        )
    ]
)
