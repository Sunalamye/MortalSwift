# MortalSwift

[![Version](https://img.shields.io/badge/version-0.5.2-blue.svg)](https://github.com/Sunalamye/MortalSwift/releases)
[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B%20%7C%20iOS%2016%2B-lightgrey.svg)](https://github.com/Sunalamye/MortalSwift)
[![License](https://img.shields.io/badge/license-AGPL--3.0-green.svg)](LICENSE)

Swift Package for the [Mortal](https://github.com/Equim-chan/Mortal) mahjong AI.
**Pure Swift + Core ML — no Rust dependency in the shipped library.**

**[繁體中文](README.md)**

> **Acknowledgment**: This project is based on [Mortal](https://github.com/Equim-chan/Mortal).
> Thanks to [Equim-chan](https://github.com/Equim-chan) for the amazing project.

---

## The problem this package solves

Mortal's model is a **fixed artifact**. It consumes a `1012 × 34` tensor, and what
each channel means (channel 23 is honba, 860 is the wait set, 889–1011 are the
per-discard expected values…) is decided by Mortal's Rust core, **libriichi**,
and baked into the weights.

Replacing the encoder means replacing the model's language. And getting it wrong
**does not raise an error** — the model happily produces a plausible-looking
recommendation built on a completely wrong understanding of the board.

So MortalSwift is not just "libriichi rewritten in Swift". It ships a parity
harness: libriichi's xcframework is linked **into the test target only**, the same
stream of game events is fed to both implementations, and every channel is compared.

### Current parity

| | Mismatches |
|---|---|
| observation (1012 channels) | **0** |
| action mask (46 entries) | **0** |

The product target has no Rust dependency; the published library does not contain
that binary. The xcframework exists purely as a test-time oracle.

> Parity proves the **input semantics are correct**, not that it **plays better**.
> The latter needs a few thousand games of evaluation, which has not been done.

---

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/Sunalamye/MortalSwift.git", from: "0.5.2")
]
```

Xcode: File → Add Package Dependencies → paste the repository URL

> The authoritative version is the **git tag** and `MortalSwiftVersion`
> (`Sources/MortalSwift/MortalSwift.swift`). The number here is only a summary —
> if they disagree, trust the code.

---

## Quick start

```swift
import MortalSwift

let bot = try MortalBot(playerId: 0, version: 4)

// Strongly typed events
_ = try await bot.react(event: .startGame(
    StartGameEvent(names: ["P0", "P1", "P2", "P3"])))

_ = try await bot.react(event: .startKyoku(StartKyokuEvent(
    bakaze: .east, kyoku: 1, honba: 0, kyotaku: 0, oya: 0,
    doraMarker: .pin(3),
    scores: [25000, 25000, 25000, 25000],
    tehais: [myHand, unknown, unknown, unknown])))

// Returns a suggested action when it is your turn, nil otherwise
if let action = try await bot.react(event: .tsumo(
    TsumoEvent(actor: 0, pai: .man(5)))) {
    print(action)
}
```

A JSON string interface is also available, compatible with the
[mjai](https://mjai.app) protocol:

```swift
let json = try await bot.react(mjaiEvent: #"{"type":"tsumo","actor":0,"pai":"5m"}"#)
```

`MortalBot` is an alias for `NativeMortalBot`, which is an `actor` — every member
needs `await`, and Core ML inference then hops off the actor onto a background task,
so the main thread is never blocked.

---

## After your own call: `inferCurrentState()`

In the MJAI protocol, **no event is sent back to you after your own chi/pon/kan
succeeds**. That means `react(event:)` never gets a chance to run, and `lastProbs`
is still whatever the model said *before* the call — while the hand has already
changed. A caller that reuses those stale probabilities (or falls back to a uniform
distribution) is playing that tile with no model input at all.

`inferCurrentState()` exists for exactly that gap: no event needed, it encodes the
**current** state, runs the model, refreshes `lastQValues` / `lastProbs` / `lastMask`,
and returns the chosen action.

```swift
// Right after your own pon succeeded (MJAI sends nothing here)
if let action = try await bot.inferCurrentState() {
    print(action)          // e.g. .dahai(...)
}
// nil when there is no legal action; last* is left untouched in that case
```

It shares the observation cache with `react` (invalidated by `PlayerState.revision`),
so "ask for the mask, then the candidates, then infer" does not re-run the expensive
EV solver three times.

---

## What's inside

```
Sources/MortalSwift/
├── MortalSwift.swift         Version string + `MortalBot` compatibility alias
├── NativeMortalBot.swift     Public interface (actor) + Core ML inference
├── Models/
│   ├── Tile.swift            Tile representation
│   ├── MJAIEvent.swift       Input events
│   ├── MJAIAction.swift      Output actions
│   └── MortalError.swift     Error type
├── State/
│   ├── PlayerState.swift     Game state
│   ├── StateUpdate.swift     Event → state
│   ├── ActionCandidate.swift What is legal right now
│   ├── KawaItem.swift        River entries (discards / called tiles)
│   ├── ObsEncoder.swift      State → 1012×34 tensor
│   ├── ActionDecoder.swift   Model output → action
│   └── SinglePlayerTables.swift
├── Algo/
│   ├── ShantenTable.swift    Shanten (table-based, used at runtime)
│   ├── Shanten.swift         Shanten (recursive, test oracle)
│   ├── HandDivision.swift    Winning-hand decomposition
│   ├── AgariCalculator.swift Yaku and fu
│   ├── Point.swift           Score conversion
│   └── SPCalculator.swift    Single-player EV solver
└── Resources/
    ├── mortal.mlmodelc       Core ML model
    └── shanten_*.bin.gz      Shanten lookup tables
```

Model I/O:

| | Shape |
|---|---|
| `obs` | `1 × 1012 × 34` |
| `mask` | `1 × 46` |
| `q_values` | `1 × 46` |

---

## Main API

### MortalBot (= `NativeMortalBot`, an `actor`)

Declarations as written in the source; being an actor, cross-actor calls need `await`.

```swift
// Constants and the bundled model
static let actionSpace = 46
static let obsChannels = 1012
static let obsWidth = 34
nonisolated static var bundledModelURL: URL? { get }

// Construction
init(playerId: Int, version: Int = 4, useBundledModel: Bool = true) throws
init(playerId: Int, version: Int = 4, modelURL: URL?) throws
var hasModel: Bool { get }

// Event driven
func react(event: MJAIEvent) async throws -> MJAIAction?
func reactSync(event: MJAIEvent) throws -> MJAIAction?
func react(mjaiEvent: String) async throws -> String?
func reactSync(mjaiEvent: String) throws -> String?

// No event needed — infer on the current state (use this after your own call)
@discardableResult
func inferCurrentState() async throws -> MJAIAction?

// Inference internals
func getLastQValues() -> [Float]
func getLastProbs() -> [Float]
func getLastSelectedAction() -> Int
func getLastMask() -> [UInt8]
func getObservation() -> [Float]
func getMask() -> [UInt8]
func getCandidateActions() -> [MJAIAction]

// How many full encodes actually ran (cache hits excluded; used by tests)
func getEncodeCount() -> Int
```

### Algorithms (usable standalone)

```swift
// Shanten: -1 = complete, 0 = tenpai, 1-6 = n away
ShantenCalculator.calcAll(tehai: [Int], lenDiv3: Int) -> Int

// Yaku and fu
AgariCalculator(tehai:isMenzen:chis:pons:minkans:ankans:
                bakaze:jikaze:winningTile:isRon:)
    .searchYakus() -> Agari?
    .hasYaku() -> Bool
    .agari(additionalHans:doras:) -> Agari?

// Scoring
Point.calc(isOya: Bool, fu: Int, han: Int) -> Point

// Per-discard tenpai / win probability and expected value, per turn
playerState.singlePlayerTables() -> [SPCandidate]?
```

### Action indices

The model's 46 outputs map to:

| Index | Action |
|:---:|------|
| 0–33 | Discard the corresponding tile |
| 34–36 | Discard red five (m / p / s) |
| 37 | Riichi |
| 38–40 | Chi (low / mid / high) |
| 41 | Pon |
| 42 | Kan |
| 43 | Agari |
| 44 | Kyuushu kyuuhai |
| 45 | Pass |

---

## Data flow

```
MJAI event
   ↓
PlayerState ── StateUpdate ──→ game state
   ↓
ObsEncoder ──→ obs [1012×34] + mask [46]
   ↓
Core ML (background, nonisolated)
   ↓
q_values [46]
   ↓
ActionDecoder ──→ MJAIAction
```

---

## Verification and performance

```bash
swift test              # 67 tests
swift test -c release   # use this for performance numbers
```

Coverage:

- **observation / mask parity** — channel-by-channel against libriichi, 19 scenarios
  (pon, opponent riichi, tedashi, red fives, furiten, kuikae, dead-wall tiles)
- **red-five action indices** — decoding 34–36, discarding a red five after riichi,
  and returning nil when no red five is in hand
- **furiten** — same-turn furiten clears on your own discard, riichi furiten is
  permanent, furiten does not block tsumo, and the flag only moves channel 861
- **kuikae** — the forbidden tiles are actually blocked, the innocent ones are not,
  and the block lifts on the next draw
- **yaku detection** — 22 assertions transcribed from libriichi's own `agari.rs` tests
- **scoring** — the full fu × han table
- **shanten** — libriichi's 19 cases, plus table-vs-recursive cross-check on
  3,000 random hands
- **encode cache / memcpy** — one encode per state revision (proven via
  `getEncodeCount()`), cached tensor identical to a fresh encode, and memcpy into
  `MLMultiArray` bit-identical to per-element boxing
- **latency budget** — exceeding it **fails** rather than just printing a number
  (separate budgets for debug and release)
- **end-to-end** — does the model give the obvious answer on an unambiguous board,
  and does `inferCurrentState()` actually infer after a call

### Performance

One observation encode (including the single-player EV solver):

| Scenario | Debug | **Release** |
|------|-------|------------|
| Tenpai | 3.5 ms | **0.1 ms** |
| 3-shanten at round start (worst) | 1,190 ms | **36.0 ms** |

These numbers are printed by the `encodeLatency` / `encodeLatencyWorstCase` tests
themselves, not copied by hand — re-run them on your machine instead of trusting
this table.

⚠️ **`swift test` builds in debug by default.** The 33× gap means debug numbers
lead to wrong conclusions about performance — this actually happened during
development.

---

## Requirements

| | Version |
|---|---|
| macOS | 13.0+ |
| iOS | 16.0+ |
| Swift | 5.9+ |
| Architecture | Apple Silicon (the Core ML model needs the Neural Engine) |

**Four-player mahjong only.** Sanma uses a `775 × 34` observation and a 44-wide
action space — a structurally different encoding — and no trained sanma weights
are publicly distributed.

---

## Changelog

### v0.5.2

- **Red-five discards get their own action indices** (34–36); the decoder only knew
  0–33 before, so holding a red five either discarded the normal five or failed to decode
- **Same-turn furiten now clears on your own discard** instead of lingering into the
  next turn; riichi furiten stays permanent
- **Kuikae is enforced**: after chi/pon the same tile and its suji are blocked, and
  the block lifts on the next draw
- **Nukidora recomputes shanten and waits** (it previously left the state stale)
- **The rinshan flag now clears**: `atRinshan` stayed true forever after the first kan,
  which made no-yaku open hands look like they could tsumo
- observation is cached per `PlayerState.revision`, so asking for the mask and the
  candidates on one state encodes once; Core ML input is now a single `memcpy`
  instead of per-element `NSNumber` boxing
- Deleted the Rust-FFI `MortalBot.swift` dead code (it was kept out of the build by
  `Package.swift`'s `exclude` — a "remove one config line and it stops compiling" trap);
  `MortalBot` is now purely a typealias for `NativeMortalBot`
- **breaking**: removed `PlayerState` fields that were written but never read
  (`isAllLast` / `isWRiichi` / `kansOnBoard` / `dorasOwned` / `dorasSeen` / `atIppatsu`)

### v0.5.1

- Added `inferCurrentState()`: MJAI sends no event after your own call, so without it
  that discard is decided from the model output taken *before* the call

### v0.5.0

- **All 1012 observation channels now match libriichi exactly** (124 were all-zero before)
- Ported yaku detection and fu calculation (`agari.rs`)
- Ported the single-player EV solver (`algo/sp`)
- Switched shanten to table lookup (36.7 ms worst case in release)
- Fixed five state-machine bugs: shanten pruning ignoring partial sets, false tenpai
  when all four copies are in hand, `shanten` lifetime, riichi not deducting 1000
  points, and calls being attached to the wrong player's river
- Tsumo agari for open hands now uses real yaku detection instead of assuming a yaku exists

### v0.4.0

- Added the libriichi parity harness (xcframework in the test target only)
- Aligned the front section of the observation layout
- **breaking**: `PlayerState.kawa` is now `[[KawaItem?]]`; `shanten` now means
  "the value for the 3n+1 hand" and is not recomputed on draw

### v0.3.0

- **breaking**: removed the Rust FFI, switched to pure Swift + Core ML
- Added `PlayerState` / `StateUpdate` / `ObsEncoder` / `ActionDecoder`

### v0.2.0

- Added strongly typed MJAI event and action APIs

---

## Design notes

Written in Traditional Chinese:

- [Why complete the Swift encoder instead of restoring libriichi](docs/decisions/obs-parity.md)
- [Implementation notes for the final 124 channels](docs/decisions/implementation-notes.md)
- [Model provenance, identification, and sanma status](docs/decisions/model-provenance.md)

---

## License

[AGPL-3.0](LICENSE), matching upstream [Mortal](https://github.com/Equim-chan/Mortal).
