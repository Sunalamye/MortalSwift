# MortalSwift

[![Version](https://img.shields.io/badge/version-0.5.2-blue.svg)](https://github.com/Sunalamye/MortalSwift/releases)
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
    .package(url: "https://github.com/Sunalamye/MortalSwift.git", from: "0.5.2")
]
```

Xcode：File → Add Package Dependencies → 貼上儲存庫 URL

> 版本以 **git tag** 與 `MortalSwiftVersion`（`Sources/MortalSwift/MortalSwift.swift`）
> 為準，README 的數字只是摘要。兩邊對不上時信程式碼，不要信這裡。

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

`MortalBot` 是 `NativeMortalBot` 的別名，本體是 `actor`——所有成員都要 `await`，
Core ML 推論再從 actor 跳到背景執行，不會卡住主執行緒。

---

## 副露之後：`inferCurrentState()`

MJAI 協定裡，自己吃／碰／槓成功之後**伺服器不會再送一個事件叫你打牌**。
對 `react(event:)` 來說這代表它根本沒有機會被呼叫，`lastProbs` 會停在副露前
那一次的結果——但手牌已經變了。呼叫端此時若拿舊機率、或退回均勻分布，
那一手等於完全沒有模型參與。

`inferCurrentState()` 是給這個缺口用的：不需要事件，直接對**當前狀態**編碼、
送進模型，更新 `lastQValues` / `lastProbs` / `lastMask`，並回傳選中的動作。

```swift
// 自己碰成功之後（MJAI 不會再送事件）
if let action = try await bot.inferCurrentState() {
    print(action)          // 例如 .dahai(...)
}
// 沒有合法動作時回 nil；此時 last* 不會被覆蓋
```

它與 `react` 共用同一份 observation 快取（失效判準是 `PlayerState.revision`），
所以「先問遮罩、再問候選、再推論」不會把最貴的期望值 DP 重跑三次。

---

## 裡面有什麼

```
Sources/MortalSwift/
├── MortalSwift.swift         版本號與 `MortalBot` 相容別名
├── NativeMortalBot.swift     對外介面（actor）＋ Core ML 推論
├── Models/
│   ├── Tile.swift            牌的表示與轉換
│   ├── MJAIEvent.swift       輸入事件
│   ├── MJAIAction.swift      輸出動作
│   └── MortalError.swift     錯誤型別
├── State/
│   ├── PlayerState.swift     對局狀態
│   ├── StateUpdate.swift     事件 → 狀態
│   ├── ActionCandidate.swift 當下可做哪些動作
│   ├── KawaItem.swift        牌河項（捨牌／被鳴走）
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

### MortalBot（＝ `NativeMortalBot`，`actor`）

以下是宣告的原樣；因為是 actor，跨 actor 呼叫都要加 `await`。

```swift
// 常數與內建模型
static let actionSpace = 46
static let obsChannels = 1012
static let obsWidth = 34
nonisolated static var bundledModelURL: URL? { get }

// 建構
init(playerId: Int, version: Int = 4, useBundledModel: Bool = true) throws
init(playerId: Int, version: Int = 4, modelURL: URL?) throws
var hasModel: Bool { get }

// 事件驅動
func react(event: MJAIEvent) async throws -> MJAIAction?
func reactSync(event: MJAIEvent) throws -> MJAIAction?
func react(mjaiEvent: String) async throws -> String?
func reactSync(mjaiEvent: String) throws -> String?

// 不靠事件，直接對當前狀態推論（副露之後用這個）
@discardableResult
func inferCurrentState() async throws -> MJAIAction?

// 推論細節
func getLastQValues() -> [Float]
func getLastProbs() -> [Float]
func getLastSelectedAction() -> Int
func getLastMask() -> [UInt8]
func getObservation() -> [Float]
func getMask() -> [UInt8]
func getCandidateActions() -> [MJAIAction]

// 真正跑過幾次完整 encode（快取命中不計，測試用）
func getEncodeCount() -> Int
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
swift test              # 67 個測試
swift test -c release   # 效能數字要看這個
```

測試涵蓋：

- **observation／mask 對拍** — 對 libriichi 逐格比對，19 套劇本（含碰、他家立直、
  手切、紅五、振聽、食い替え、王牌區死牌）
- **紅五動作索引** — 34–36 的解碼、立直後打紅五、手上沒紅五時該回 nil
- **振聽** — 同巡振聽在自家打牌後解除、立直振聽永久、振聽不擋自摸、
  且只影響 channel 861
- **食い替え** — 副露後該禁的禁到、不該禁的沒被牽連、下次摸牌時解除
- **役種判定** — libriichi `agari.rs` 逐字移植的 22 條斷言
- **點數換算** — 完整符 × 飜對照表
- **向聽** — libriichi 的 19 個案例，外加查表版與遞迴版在 3000 手隨機牌上互相對照
- **編碼快取／memcpy** — 同一個狀態版本只 encode 一次（`getEncodeCount()` 證明），
  且快取值與重算值逐格相同；memcpy 進 `MLMultiArray` 與逐格裝箱結果相同
- **延遲門檻** — 超標會**失敗**而不只是印數字（Debug／Release 各一組門檻）
- **端到端** — 模型在答案毫無爭議的局面上是否給出該答案，以及副露後
  `inferCurrentState()` 是否真的推得動

### 效能

單次 observation 編碼（含單人期望值推演）：

| 情境 | Debug | **Release** |
|------|-------|------------|
| 聽牌 | 3.5 ms | **0.1 ms** |
| 開局三向聽（最壞） | 1,190 ms | **36.0 ms** |

數字由 `encodeLatency` / `encodeLatencyWorstCase` 兩個測試自己印出來，
不是手抄的——換機器就重跑一次，不要相信這張表。

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

### v0.5.2

- **打紅五有自己的動作索引**（34–36）：先前解碼只認 0–33，手上有紅五時會打出
  普通五或直接解不出來
- **同巡振聽改成自家打牌後解除**，不再一路掛到下一巡；立直振聽維持永久
- **實作食い替え禁手**：吃碰之後禁打現物與筋牌，下次摸牌時解除
- **拔北後補算向聽與等待**（先前拔北不會讓狀態重算）
- **嶺上旗標會熄滅**：`atRinshan` 先前槓過一次就一路 true，害副露無役手被判成
  可以自摸和
- observation 以 `PlayerState.revision` 為準快取，同一狀態連問遮罩／候選只算一次；
  Core ML 輸入改整塊 `memcpy`，不再逐格裝箱 `NSNumber`
- 刪掉走 Rust FFI 的 `MortalBot.swift` 死碼（它靠 `Package.swift` 的 `exclude`
  排在編譯外，是「移掉一行組態就編不過」的陷阱），`MortalBot` 現在只是
  `NativeMortalBot` 的 typealias
- **breaking**：移除只被寫、沒有被讀的 `PlayerState` 欄位
  （`isAllLast`／`isWRiichi`／`kansOnBoard`／`dorasOwned`／`dorasSeen`／`atIppatsu`）

### v0.5.1

- 新增 `inferCurrentState()`：MJAI 在自家副露之後不會再送事件，
  沒有它的話那一手拿到的是副露前的舊機率

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
