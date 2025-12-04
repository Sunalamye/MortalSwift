# MortalSwift

[![Version](https://img.shields.io/badge/version-0.2.0-blue.svg)](https://github.com/Sunalamye/MortalSwift)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20iOS-lightgrey.svg)](https://github.com/Sunalamye/MortalSwift)
[![License](https://img.shields.io/badge/license-AGPL--3.0-green.svg)](LICENSE)

Swift Package for [Mortal](https://github.com/Equim-chan/Mortal) Mahjong AI - Native Swift integration via Rust FFI + Core ML.

> **Acknowledgment**: This project is based on [Mortal](https://github.com/Equim-chan/Mortal) Mahjong AI. Thanks to [Equim-chan](https://github.com/Equim-chan) for the amazing project.

**[繁體中文](README.md)**

## Installation

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Sunalamye/MortalSwift.git", from: "0.2.0")
]
```

Or in Xcode: File → Add Package Dependencies → Enter the repository URL

## Usage

```swift
import MortalSwift

// 1. Initialize Bot (without Core ML - uses default strategy)
let bot = try MortalBot(playerId: 0, version: 4, useBundledModel: false)

// 2. Or with bundled Core ML model (default)
let bot = try MortalBot(playerId: 0, version: 4)

// 3. Or with custom Core ML model URL
let modelURL = Bundle.main.url(forResource: "mortal", withExtension: "mlmodelc")
let bot = try MortalBot(playerId: 0, version: 4, modelURL: modelURL)

// 4. Process MJAI events (async - recommended)
let event = #"{"type":"tsumo","actor":0,"pai":"5m"}"#
if let response = try await bot.react(mjaiEvent: event) {
    print("Bot action: \(response)")
}

// 5. Get observation tensor (for custom inference)
let obs = await bot.getObservation()   // [Float] - 1012*34 values
let mask = await bot.getMask()         // [UInt8] - 46 values (0/1)

// 6. Manually select action
let response = await bot.selectActionManually(actionIdx: 45)  // Pass

// 7. Get last inference results
let qValues = await bot.getLastQValues()  // Q-values from Core ML
let probs = await bot.getLastProbs()      // Softmax probabilities
```

### Sync API (for compatibility)

```swift
// Use reactSync() when async is not available
if let response = try bot.reactSync(mjaiEvent: event) {
    print("Bot action: \(response)")
}
```

## Package Structure

```
MortalSwift/
├── Package.swift
├── README.md
└── Sources/
    ├── CLibRiichi/              # C library wrapper
    │   ├── include/
    │   │   ├── libriichi.h      # C header
    │   │   └── module.modulemap
    │   ├── libriichi.xcframework/  # Multi-platform static library
    │   │   ├── ios-arm64/          # iOS device (arm64)
    │   │   ├── ios-arm64-simulator/ # iOS simulator (arm64)
    │   │   └── macos-arm64/        # macOS (arm64)
    │   └── shim.c
    └── MortalSwift/             # Swift wrapper
        ├── MortalBot.swift      # Main API
        └── MortalSwift.swift
```

## API

### MortalBot

`MortalBot` is an **actor** that provides thread-safe async access to the Mahjong AI.

```swift
public actor MortalBot {
    // Initialize with bundled model
    init(playerId: UInt8, version: UInt32 = 4, useBundledModel: Bool = true) throws

    // Initialize with custom model URL
    init(playerId: UInt8, version: UInt32 = 4, modelURL: URL?) throws

    // Process MJAI event (async - runs Core ML in background)
    func react(mjaiEvent: String) async throws -> String?

    // Process MJAI event (sync - for compatibility)
    func reactSync(mjaiEvent: String) throws -> String?

    // Get current observation tensor
    func getObservation() -> [Float]

    // Get current action mask
    func getMask() -> [UInt8]

    // Get available actions (JSON)
    func getCandidates() -> String?

    // Manually select action
    func selectActionManually(actionIdx: Int) -> String?

    // Get last inference results
    func getLastQValues() -> [Float]
    func getLastProbs() -> [Float]
    func getLastSelectedAction() -> Int
    func getLastMask() -> [UInt8]

    // Check if Core ML model is loaded
    var hasModel: Bool { get }

    // Get bundled model URL
    static var bundledModelURL: URL? { get }
}
```

> **Note**: Since `MortalBot` is an actor, all method calls require `await` in async contexts.

### MahjongAction

```swift
public enum MahjongAction: Int {
    case discard1m = 0   // Discard 1-man
    // ... 0-33: Discard tiles
    case riichi = 37     // Riichi
    case chiLow = 38     // Chi (low)
    case chiMid = 39     // Chi (mid)
    case chiHigh = 40    // Chi (high)
    case pon = 41        // Pon
    case kan = 42        // Kan
    case hora = 43       // Hora (win)
    case ryukyoku = 44   // Ryukyoku (draw)
    case pass = 45       // Pass
}
```

## Data Flow

```
MJAI JSON Event
      ↓
┌─────────────────────────┐
│  libriichi.a (Rust)     │
│  • Parse event          │
│  • Update game state    │
│  • Generate obs tensor  │
└─────────────────────────┘
      ↓
obs: [1012×34], mask: [46]
      ↓
┌─────────────────────────┐
│  Core ML (background)   │  ← async, nonisolated
│  • Neural network       │
│  • Output Q-values      │
└─────────────────────────┘
      ↓
action_idx: 0-45
      ↓
┌─────────────────────────┐
│  libriichi.a (Rust)     │
│  • Action idx → MJAI    │
└─────────────────────────┘
      ↓
MJAI JSON Response
```

## Concurrency Architecture

`MortalBot` uses Swift's modern concurrency model:

- **Actor isolation**: Thread-safe state management
- **Async inference**: Core ML runs in background via `Task.detached`
- **Non-blocking**: UI thread is never blocked during inference

```
react() [async, actor-isolated]
    └── selectAction() [async]
            └── runInferenceInBackground() [nonisolated]
                    └── Task.detached { Core ML inference }
```

## Requirements

- macOS 13+ / iOS 16+
- Swift 5.9+
- Core ML model (optional): `mortal.mlmodelc`

## License

This project is licensed under **AGPL-3.0**, consistent with the upstream [Mortal](https://github.com/Equim-chan/Mortal) project.

See [LICENSE](LICENSE) for details.
