// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

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
            resources: [
                .copy("Resources/mortal.mlmodelc"),
                // 向聽查表（見 ShantenTable.swift）
                .copy("Resources/shanten_suhai.bin.gz"),
                .copy("Resources/shanten_jihai.bin.gz"),
            ]
        ),

        // ── 僅供測試的 libriichi oracle ───────────────────────────────
        //
        // 模型（mortal.mlmodelc）是固定成品，它訓練時看到的 1012 個 channel
        // 各自代表什麼，是由 libriichi 的編碼決定的。純 Swift 版要接管推論，
        // 唯一能證明「語意一致」的方式就是拿 libriichi 當基準逐 channel 對拍。
        //
        // 因此把 xcframework 掛回來，但**只給 test target 用**：
        // 產品 target MortalSwift 仍然沒有任何 Rust 依賴，
        // 發布出去的 library 不含這個 binary。
        .binaryTarget(
            name: "LibRiichi",
            path: "Sources/CLibRiichi/libriichi.xcframework"
        ),

        .target(
            name: "CLibRiichi",
            dependencies: ["LibRiichi"],
            path: "Sources/CLibRiichi",
            sources: ["shim.c"],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("include")
            ],
            linkerSettings: [
                .linkedLibrary("c++")
            ]
        ),

        .testTarget(
            name: "MortalSwiftTests",
            dependencies: ["MortalSwift", "CLibRiichi"]
        ),
    ]
)
