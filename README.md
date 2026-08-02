# MortalSwift

[![Version](https://img.shields.io/badge/version-0.5.0-blue.svg)](https://github.com/Sunalamye/MortalSwift/releases)
[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B%20%7C%20iOS%2016%2B-lightgrey.svg)](https://github.com/Sunalamye/MortalSwift)
[![License](https://img.shields.io/badge/license-AGPL--3.0-green.svg)](LICENSE)

[Mortal](https://github.com/Equim-chan/Mortal) 麻將 AI 的 Swift Package。
**純 Swift + Core ML，產品端零 Rust 依賴。**

**[English](README_en.md)**

> **致謝**：本專案基於 [Mortal](https://github.com/Equim-chan/Mortal)，
> 感謝 [Equim-chan](https://github.com/Equim-chan) 開發的優秀專案。

---

## 這個套件解決的問題

Mortal 的模型是**固定成品**。它吃的是一個 `1012 × 34` 的張量，每一格代表什麼
（第 23 格是本場、第 860 格是聽牌、第 889–1011 格是每張打牌的期望值…）
都由 Mortal 的 Rust 核心 **libriichi** 決定，寫死在權重裡。

換掉編碼器等於換掉模型的語言。而編碼錯了**不會報錯**——模型會照樣算出一個
看起來很正常的推薦，只是那個推薦建立在完全錯誤的理解上。

所以 MortalSwift 不只是「把 libriichi 用 Swift 重寫一遍」，它還附帶一套對拍機制：
把 libriichi 的 xcframework 掛在 **test target**，同一串對局事件同時餵給兩邊，
逐格比對輸出。

### 目前的對拍結果

| 項目 | 落差 |
|------|------|
| observation（1012 channel） | **0** |
| action mask（46 格） | **0** |

產品 target 沒有任何 Rust 依賴，發布出去的 library 不含那個 binary。
xcframework 純粹是測試時的基準。

> 對拍證明的是**輸入語意正確**，不是**打得比較好**。
> 後者需要跑幾千局的評測環境才說得準。

---

## 安裝

```swift
dependencies: [
    .package(url: "https://github.com/Sunalamye/MortalSwift.git", from: "0.5.0")
]
```

Xcode：File → Add Package Dependencies → 貼上儲存庫 URL

---

## 快速開始

```swift
import MortalSwift

let bot = try MortalBot(playerId: 0, version: 4)

// 強型別事件
_ = try await bot.react(event: .startGame(
    StartGameEvent(names: ["P0", "P1", "P2", "P3"])))

_ = try await bot.react(event: .startKyoku(StartKyokuEvent(
    bakaze: .east, kyoku: 1, honba: 0, kyotaku: 0, oya: 0,
    doraMarker: .pin(3),
    scores: [25000, 25000, 25000, 25000],
    tehais: [myHand, unknown, unknown, unknown])))

// 輪到自己時回傳建議動作，否則 nil
if let action = try await bot.react(event: .tsumo(
    TsumoEvent(actor: 0, pai: .man(5)))) {
    print(action)   // 例如 .dahai(...)
}
```

也支援 JSON 字串介面（與 [mjai](https://mjai.app) 協定相容）：

```swift
let json = try await bot.react(mjaiEvent: #"{"type":"tsumo","actor":0,"pai":"5m"}"#)
```

`MortalBot` 是 `actor`，Core ML 推論在背景執行，不會卡住主執行緒。

---

## 裡面有什麼

```
Sources/MortalSwift/
├── MortalSwift.swift         版本號與 `MortalBot` 相容別名
├── NativeMortalBot.swift     對外介面（actor）＋ Core ML 推論
├── Models/
│   ├── Tile.swift            牌的表示與轉換
│   ├── MJAIEvent.swift       輸入事件
│   └── MJAIAction.swift      輸出動作
├── State/
│   ├── PlayerState.swift     對局狀態
│   ├── StateUpdate.swift     事件 → 狀態
│   ├── ObsEncoder.swift      狀態 → 1012×34 張量
│   ├── ActionDecoder.swift   模型輸出 → 動作
│   └── SinglePlayerTables.swift
├── Algo/
│   ├── ShantenTable.swift    向聽（查表，實際使用）
│   ├── Shanten.swift         向聽（遞迴，測試對照用）
│   ├── HandDivision.swift    和了形拆解
│   ├── AgariCalculator.swift 役種與符計算
│   ├── Point.swift           點數換算
│   └── SPCalculator.swift    單人期望值推演
└── Resources/
    ├── mortal.mlmodelc       Core ML 模型
    └── shanten_*.bin.gz      向聽查表
```

模型輸入輸出：

| | 形狀 |
|---|---|
| `obs` | `1 × 1012 × 34` |
| `mask` | `1 × 46` |
| `q_values` | `1 × 46` |

---

## 主要 API

### MortalBot

```swift
init(playerId: Int, version: Int = 4, useBundledModel: Bool = true) throws
init(playerId: Int, version: Int = 4, modelURL: URL?) throws

func react(event: MJAIEvent) async throws -> MJAIAction?
func react(mjaiEvent: String) async throws -> String?
func reactSync(event: MJAIEvent) throws -> MJAIAction?

// 推論細節
var hasModel: Bool { get async }
func getLastQValues() async -> [Float]
func getLastProbs() async -> [Float]
func getObservation() async -> [Float]
func getMask() async -> [UInt8]
func getCandidateActions() async -> [MahjongAction]
func selectActionManually(_ index: Int) async
func reset() async
```

### 演算法（可獨立使用）

```swift
// 向聽數：-1 和了、0 聽牌、1-6 一到六向聽
ShantenCalculator.calcAll(tehai: [Int], lenDiv3: Int) -> Int

// 役種與符
AgariCalculator(tehai:isMenzen:chis:pons:minkans:ankans:
                bakaze:jikaze:winningTile:isRon:)
    .searchYakus() -> Agari?
    .hasYaku() -> Bool
    .agari(additionalHans:doras:) -> Agari?

// 點數
Point.calc(isOya: Bool, fu: Int, han: Int) -> Point

// 單人期望值：每張打牌在每一巡的聽牌率／和牌率／期望點數
playerState.singlePlayerTables() -> [SPCandidate]?
```

### 動作索引

模型輸出的 46 格對應：

| 索引 | 動作 |
|:---:|------|
| 0–33 | 打出對應的牌 |
| 34–36 | 打出紅五（萬／筒／索） |
| 37 | 立直 |
| 38–40 | 吃（下／中／上） |
| 41 | 碰 |
| 42 | 槓 |
| 43 | 和 |
| 44 | 九種九牌 |
| 45 | 跳過 |

---

## 資料流程

```
MJAI 事件
   ↓
PlayerState ── StateUpdate ──→ 對局狀態
   ↓
ObsEncoder ──→ obs [1012×34] + mask [46]
   ↓
Core ML（背景執行，nonisolated）
   ↓
q_values [46]
   ↓
ActionDecoder ──→ MJAIAction
```

---

## 驗證與效能

```bash
swift test              # 47 個測試
swift test -c release   # 效能數字要看這個
```

測試涵蓋：

- **observation 對拍** — 對 libriichi 逐格比對，兩套劇本（含碰、他家立直、手切）
- **役種判定** — libriichi `agari.rs` 自己的 24 個案例
- **點數換算** — 完整符 × 飜對照表
- **向聽** — libriichi 的 19 個案例，外加查表版與遞迴版在 3000 手隨機牌上互相對照
- **端到端** — 模型在答案毫無爭議的局面上是否給出該答案

### 效能

單次 observation 編碼（含單人期望值推演）：

| 情境 | Debug | **Release** |
|------|-------|------------|
| 聽牌 | 3.6 ms | **0.1 ms** |
| 開局三向聽（最壞） | 1,225 ms | **36.7 ms** |

⚠️ **`swift test` 預設是 debug build。** 兩者差 33 倍，
拿 debug 數字判斷效能會得到錯誤結論（這件事實際發生過，見設計紀錄）。

---

## 需求

| | 版本 |
|---|---|
| macOS | 13.0+ |
| iOS | 16.0+ |
| Swift | 5.9+ |
| 架構 | Apple Silicon（Core ML 模型需要 Neural Engine） |

**只支援四人麻將。** 三麻的 observation 是 `775 × 34`、動作空間 44，
結構完全不同；而且公開管道找不到訓練好的三麻權重
（詳見[模型來源紀錄](docs/decisions/model-provenance.md)）。

---

## 更新日誌

### v0.5.0

- **observation 1012 格全部與 libriichi 逐格一致**（先前有 124 格送全 0）
- 移植役種判定與符計算（`agari.rs`）
- 移植單人期望值推演（`algo/sp`）
- 向聽改用查表（最壞情況 Release 下 36.7 ms）
- 修正五個狀態機錯誤：向聽剪枝漏算搭子、四枚同牌的假單騎、
  `shanten` 生命週期、立直成立沒扣分、吃碰槓掛錯河項
- 副露手的自摸判定改用真正的役種判定，不再樂觀假設有役

### v0.4.0

- 建立 libriichi 對拍機制（xcframework 只掛 test target）
- 對齊 observation 前段佈局
- **breaking**：`PlayerState.kawa` 型別改為 `[[KawaItem?]]`；
  `shanten` 語意改為「3n+1 手牌的值」，摸牌後不重算

### v0.3.0

- **breaking**：移除 Rust FFI，改為純 Swift + Core ML
- 新增 `PlayerState` / `StateUpdate` / `ObsEncoder` / `ActionDecoder`

### v0.2.0

- 新增強型別 MJAI 事件與動作 API

---

## 設計紀錄

- [observation 編碼的方案取捨](docs/decisions/obs-parity.md)
- [補完最後 124 格的實作筆記](docs/decisions/implementation-notes.md)
- [模型來源、鑑定方法與三麻現況](docs/decisions/model-provenance.md)

---

## 授權條款

[AGPL-3.0](LICENSE)，與上游 [Mortal](https://github.com/Equim-chan/Mortal) 一致。
