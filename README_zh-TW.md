# MortalSwift

[![Version](https://img.shields.io/badge/version-0.0.1-blue.svg)](https://github.com/Sunalamye/MortalSwift)
[![License](https://img.shields.io/badge/license-AGPL--3.0-green.svg)](LICENSE)

[Mortal](https://github.com/Equim-chan/Mortal) 麻將 AI 的 Swift Package - 透過 Rust FFI + Core ML 實現原生 Swift 整合。

> **致謝**：本專案基於 [Mortal](https://github.com/Equim-chan/Mortal) 麻將 AI，感謝 [Equim-chan](https://github.com/Equim-chan) 開發的優秀專案。

**[English](README.md)**

## 安裝

### Swift Package Manager

在 `Package.swift` 中加入：

```swift
dependencies: [
    .package(url: "https://github.com/Sunalamye/MortalSwift.git", from: "0.0.1")
]
```

或在 Xcode 中：File → Add Package Dependencies → 輸入儲存庫 URL

## 使用方式

```swift
import MortalSwift

// 1. 初始化 Bot（不帶 Core ML - 使用預設策略）
let bot = try MortalBot(playerId: 0, version: 4)

// 2. 或帶 Core ML 模型
let modelURL = Bundle.main.url(forResource: "mortal", withExtension: "mlmodelc")
let bot = try MortalBot(playerId: 0, version: 4, modelURL: modelURL)

// 3. 處理 MJAI 事件
let event = #"{"type":"tsumo","actor":0,"pai":"5m"}"#
if let response = try bot.react(mjaiEvent: event) {
    print("Bot action: \(response)")
}

// 4. 取得觀察張量（用於自訂推理）
let obs = bot.getObservation()   // [Float] - 1012*34 個值
let mask = bot.getMask()         // [UInt8] - 46 個值 (0/1)

// 5. 手動選擇動作
let response = bot.selectActionManually(actionIdx: 45)  // Pass
```

## Package 結構

```
MortalSwift/
├── Package.swift
├── README.md
└── Sources/
    ├── CLibRiichi/              # C 函式庫包裝
    │   ├── include/
    │   │   ├── libriichi.h      # C 標頭檔
    │   │   └── module.modulemap
    │   ├── libriichi.a          # Rust 靜態函式庫
    │   └── shim.c
    └── MortalSwift/             # Swift 封裝
        ├── MortalBot.swift      # 主要 API
        └── MortalSwift.swift
```

## API

### MortalBot

```swift
public class MortalBot {
    // 初始化
    init(playerId: UInt8, version: UInt32 = 4, modelURL: URL? = nil) throws

    // 處理 MJAI 事件，回傳回應 JSON
    func react(mjaiEvent: String) throws -> String?

    // 取得當前觀察張量
    func getObservation() -> [Float]

    // 取得當前動作遮罩
    func getMask() -> [UInt8]

    // 取得可用動作（JSON）
    func getCandidates() -> String?

    // 手動選擇動作
    func selectActionManually(actionIdx: Int) -> String?
}
```

### MahjongAction

```swift
public enum MahjongAction: Int {
    case discard1m = 0   // 打 1 萬
    // ... 0-33: 打牌
    case riichi = 37     // 立直
    case chiLow = 38     // 吃（低）
    case chiMid = 39     // 吃（中）
    case chiHigh = 40    // 吃（高）
    case pon = 41        // 碰
    case kan = 42        // 槓
    case hora = 43       // 和
    case ryukyoku = 44   // 流局
    case pass = 45       // 過
}
```

## 資料流程

```
MJAI JSON 事件
      ↓
┌─────────────────────────┐
│  libriichi.a (Rust)     │
│  • 解析事件             │
│  • 更新遊戲狀態         │
│  • 產生觀察張量         │
└─────────────────────────┘
      ↓
obs: [1012×34], mask: [46]
      ↓
┌─────────────────────────┐
│  Core ML（可選）        │
│  • 神經網路推理         │
│  • 輸出 Q 值            │
└─────────────────────────┘
      ↓
action_idx: 0-45
      ↓
┌─────────────────────────┐
│  libriichi.a (Rust)     │
│  • 動作索引 → MJAI JSON │
└─────────────────────────┘
      ↓
MJAI JSON 回應
```

## 需求

- macOS 13+ / iOS 16+
- Swift 5.9+
- Core ML 模型（可選）：`mortal.mlmodelc`

## 授權條款

本專案採用 **AGPL-3.0** 授權，與上游 [Mortal](https://github.com/Equim-chan/Mortal) 專案保持一致。

詳見 [LICENSE](LICENSE) 檔案。
