// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import Foundation

// Get the package directory for absolute paths
let packageDir = URL(fileURLWithPath: #file).deletingLastPathComponent().path

let package = Package(
    name: "MortalSwift",
    platforms: [
        .macOS(.v13),
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "MortalSwift",
            targets: ["MortalSwift"]
        ),
    ],
    targets: [
        // C library wrapper for libriichi (now Python-free)
        .target(
            name: "CLibRiichi",
            path: "Sources/CLibRiichi",
            sources: ["shim.c"],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("include")
            ],
            linkerSettings: [
                .linkedLibrary("riichi"),
                .linkedLibrary("c++"),
                .linkedLibrary("resolv"),
                .linkedLibrary("iconv"),
                .unsafeFlags([
                    "-L\(packageDir)/Sources/CLibRiichi"
                ])
            ]
        ),

        // Main Swift target
        .target(
            name: "MortalSwift",
            dependencies: ["CLibRiichi"],
            path: "Sources/MortalSwift",
            resources: [
                .copy("Resources/mortal.mlmodelc")
            ]
        ),

        .testTarget(
            name: "MortalSwiftTests",
            dependencies: ["MortalSwift"]
        ),
    ]
)
