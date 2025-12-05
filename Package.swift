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
        // 純 Swift 實現，無需 Rust FFI
        .library(
            name: "MortalSwift",
            targets: ["MortalSwift"]
        ),
    ],
    targets: [
        // 主要 Swift target - 純 Swift 實現
        .target(
            name: "MortalSwift",
            dependencies: [],
            path: "Sources/MortalSwift",
            exclude: [
                "MortalBot.swift"  // 排除舊的 FFI 版本
            ],
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
