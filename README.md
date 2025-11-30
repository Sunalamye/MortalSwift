# MortalSwift

[![Version](https://img.shields.io/badge/version-0.0.1-blue.svg)](https://github.com/Sunalamye/MortalSwift)
[![License](https://img.shields.io/badge/license-AGPL--3.0-green.svg)](LICENSE)

Swift Package for [Mortal](https://github.com/Equim-chan/Mortal) Mahjong AI - 使用 Rust FFI + Core ML 實現原生 Swift 調用。

> **致謝**: 本項目基於 [Mortal](https://github.com/Equim-chan/Mortal) 麻將 AI，感謝 [Equim-chan](https://github.com/Equim-chan) 開發的優秀項目。

## 安装

### Swift Package Manager

在 `Package.swift` 中添加：

```swift
dependencies: [
    .package(path: "../MortalSwift")  // 或使用 URL
]
```

或在 Xcode 中：File → Add Package Dependencies → 添加本地路径

## 使用

```swift
import MortalSwift

// 1. 初始化 Bot (不带 Core ML - 使用默认策略)
let bot = try MortalBot(playerId: 0, version: 4)

// 2. 或带 Core ML 模型
let modelURL = Bundle.main.url(forResource: "mortal", withExtension: "mlmodelc")
let bot = try MortalBot(playerId: 0, version: 4, modelURL: modelURL)

// 3. 处理 MJAI 事件
let event = #"{"type":"tsumo","actor":0,"pai":"5m"}"#
if let response = try bot.react(mjaiEvent: event) {
    print("Bot action: \(response)")
}

// 4. 获取观察张量 (用于自定义推理)
let obs = bot.getObservation()   // [Float] - 1012*34 个值
let mask = bot.getMask()         // [UInt8] - 46 个值 (0/1)

// 5. 手动选择动作
let response = bot.selectActionManually(actionIdx: 45)  // Pass
```

## Package 结构

```
MortalSwift/
├── Package.swift
├── README.md
└── Sources/
    ├── CLibRiichi/              # C 库包装
    │   ├── include/
    │   │   ├── libriichi.h      # C 头文件
    │   │   └── module.modulemap
    │   ├── libriichi.a          # Rust 静态库 (60MB)
    │   └── shim.c
    └── MortalSwift/             # Swift 封装
        ├── MortalBot.swift      # 主要 API
        └── MortalSwift.swift
```

## API

### MortalBot

```swift
public class MortalBot {
    // 初始化
    init(playerId: UInt8, version: UInt32 = 4, modelURL: URL? = nil) throws

    // 处理 MJAI 事件，返回响应 JSON
    func react(mjaiEvent: String) throws -> String?

    // 获取当前观察张量
    func getObservation() -> [Float]

    // 获取当前动作掩码
    func getMask() -> [UInt8]

    // 获取可用动作 (JSON)
    func getCandidates() -> String?

    // 手动选择动作
    func selectActionManually(actionIdx: Int) -> String?
}
```

### MahjongAction

```swift
public enum MahjongAction: Int {
    case discard1m = 0   // 打 1 万
    // ... 0-33: 打牌
    case riichi = 37     // 立直
    case chiLow = 38     // 吃 (低)
    case chiMid = 39     // 吃 (中)
    case chiHigh = 40    // 吃 (高)
    case pon = 41        // 碰
    case kan = 42        // 杠
    case hora = 43       // 和
    case ryukyoku = 44   // 流局
    case pass = 45       // 过
}
```

## 数据流

```
MJAI JSON 事件
      ↓
┌─────────────────────────┐
│  libriichi.a (Rust)     │
│  • 解析事件             │
│  • 更新游戏状态         │
│  • 生成观察张量         │
└─────────────────────────┘
      ↓
obs: [1012×34], mask: [46]
      ↓
┌─────────────────────────┐
│  Core ML (可选)         │
│  • 神经网络推理         │
│  • 输出 Q 值            │
└─────────────────────────┘
      ↓
action_idx: 0-45
      ↓
┌─────────────────────────┐
│  libriichi.a (Rust)     │
│  • 动作索引 → MJAI JSON │
└─────────────────────────┘
      ↓
MJAI JSON 响应
```

## 要求

- macOS 13+ / iOS 16+
- Swift 5.9+
- Core ML 模型 (可选): `mortal.mlpackage`

## 許可證

本項目採用 **AGPL-3.0** 授權，與上游 [Mortal](https://github.com/Equim-chan/Mortal) 項目保持一致。

詳見 [LICENSE](LICENSE) 文件。
