# MortalSwift

[![Version](https://img.shields.io/badge/version-0.0.1-blue.svg)](https://github.com/Sunalamye/MortalSwift)
[![License](https://img.shields.io/badge/license-AGPL--3.0-green.svg)](LICENSE)

Swift Package for [Mortal](https://github.com/Equim-chan/Mortal) Mahjong AI - Native Swift integration via Rust FFI + Core ML.

> **Acknowledgment**: This project is based on [Mortal](https://github.com/Equim-chan/Mortal) Mahjong AI. Thanks to [Equim-chan](https://github.com/Equim-chan) for the amazing project.

**[繁體中文](README_zh-TW.md)**

## Installation

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Sunalamye/MortalSwift.git", from: "0.0.1")
]
```

Or in Xcode: File → Add Package Dependencies → Enter the repository URL

## Usage

```swift
import MortalSwift

// 1. Initialize Bot (without Core ML - uses default strategy)
let bot = try MortalBot(playerId: 0, version: 4)

// 2. Or with Core ML model
let modelURL = Bundle.main.url(forResource: "mortal", withExtension: "mlmodelc")
let bot = try MortalBot(playerId: 0, version: 4, modelURL: modelURL)

// 3. Process MJAI events
let event = #"{"type":"tsumo","actor":0,"pai":"5m"}"#
if let response = try bot.react(mjaiEvent: event) {
    print("Bot action: \(response)")
}

// 4. Get observation tensor (for custom inference)
let obs = bot.getObservation()   // [Float] - 1012*34 values
let mask = bot.getMask()         // [UInt8] - 46 values (0/1)

// 5. Manually select action
let response = bot.selectActionManually(actionIdx: 45)  // Pass
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
    │   ├── libriichi.a          # Rust static library
    │   └── shim.c
    └── MortalSwift/             # Swift wrapper
        ├── MortalBot.swift      # Main API
        └── MortalSwift.swift
```

## API

### MortalBot

```swift
public class MortalBot {
    // Initialize
    init(playerId: UInt8, version: UInt32 = 4, modelURL: URL? = nil) throws

    // Process MJAI event, returns response JSON
    func react(mjaiEvent: String) throws -> String?

    // Get current observation tensor
    func getObservation() -> [Float]

    // Get current action mask
    func getMask() -> [UInt8]

    // Get available actions (JSON)
    func getCandidates() -> String?

    // Manually select action
    func selectActionManually(actionIdx: Int) -> String?
}
```

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
│  Core ML (optional)     │
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

## Requirements

- macOS 13+ / iOS 16+
- Swift 5.9+
- Core ML model (optional): `mortal.mlmodelc`

## License

This project is licensed under **AGPL-3.0**, consistent with the upstream [Mortal](https://github.com/Equim-chan/Mortal) project.

See [LICENSE](LICENSE) for details.
