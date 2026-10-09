# AkagiSanma implementation notes

來源：Akagi `native_bot`（v3，commit `cd68865`，Apache-2.0，見 `LICENSE-Akagi.txt`）。

| Swift | Rust 對應 |
|---|---|
| `SanmaTiles` | `tiles.rs`（僅三麻分支）＋ riichienv `standard_next_dora_tile` |
| `SanmaModel` | `model.rs`（candle）→ 自寫 safetensors 讀取＋vDSP_mmul |
| `SanmaActionCodec` / `SanmaAction` | `action_codec.rs` ＋ riichienv `ActionEncoder::ThreePlayer` |
| `SanmaEncInput` / `SanmaSeat` | `obs.rs` 的 `EncInput::encode`（num_players = 3） |
| `SanmaState`（`SanmaState.swift`） | riichienv `GameState3P::apply_mjai_event`（mjai 重播路徑）＋ `mjai_compat.rs` ＋ `chankan.rs` |
| `SanmaState.legalActions()`（`SanmaLegal.swift`） | riichienv `state_3p/legal_actions.rs`＋`sanma.rs` 的拔北；和牌只看形狀 |
| `SanmaState.encInput()`（`SanmaAdapt.swift`） | `adapt.rs` 的 `enc_input_3p` |
| `SanmaEngine` | `engine.rs`（三麻分支、`predict_reach_discard_3p`） |

驗證：
- `parity_3p.json`（PyTorch 參考 logits）：max|Δ| 1.53e-5、argmax 54。
- `obs_golden_3p.json`：由 Rust `EncInput::encode` 產生的 3 組輸入（Akagi 測試 sample、涵蓋寶牌環／副露／拔北／截斷的 varied、全零），Swift 逐值完全相等。

## S1b（2026-10-09）

- 狀態語意照 riichienv 的 mjai 重播路徑移植，不照「直覺」：`turn_count` 恆 0、立直宣言牌面恆空（重播路徑不寫 `riichi_sutehais`）、被叫走的牌留在河裡、`last_discard` 只被 dahai 與搶槓開窗改寫、`drawn_tile` 在暗槓／加槓／大明槓／拔北後殘留、`reach_accepted` 才扣 1000、`is_first_turn` 不清除（沒人副露就一直可九種九牌）。與 S1a `state-semantics.md` 十條逐條一致。
- 合法動作是實體列舉（同 tid 的重複牌各一筆），`forced` 依實體數。
- `decide(authorized:)` 是給 Naki 的 oplist 授權閘：捨牌與 pass 永遠保留，其餘類別要授權。
- 驗證：S1a 13 seeds × 2 seats、1985 個決策點，經授權閘後 obs、實體合法集合、mask、logits（max |Δ| 1.5e-5）、排名、forced、最終動作（含立直宣言牌）全部一致。fixture 由 `compact_fixtures.py`（Naki `.swfd/logs/s1b-sanma-state/`）壓成 `Tests/AkagiSanmaTests/Fixtures/s1a/`（5.1 MB）。

## Deviations

- 「全零輸入 → 全零」不成立：Rust 版場風、自風一律以 one-hot 寫入（預設東，緊湊索引 20，第 25、26 面）。測試改為斷言只剩這兩格非零，與 Rust golden 一致。
- action codec 測試原為四麻案例，改寫為三麻等價案例；赤五優先測試改用 5p（tid 52/53），因三麻沒有 5m。
- 每家相關平面只取前 3 個座位（Rust 若傳入超過 3 家會越界 panic）；不足 3 家時與 Rust 一樣跳過空位。
- `SanmaModel` 只支援三麻幾何；載入時檢查每個張量的 dtype 與 shape，不符即拋錯。
- 和牌（tsumo／ron）只看形狀、不判役，役交給上層 oplist。未經閘時會比 Rust 多出無役的和牌：fixture 中 1 次 tsumo、5 個只有 ron＋pass 的回應窗口。搶槓本身是役，所以搶槓窗口與 Rust 完全等價。
- 拔北一律計數；手裡找得到北就移除，找不到（他家手牌是 `?`）就只計數，並以 tid 120 判他家的拔北榮和。Rust 在找不到北時不計數，所以接 Naki 這種他家手牌為 `?` 的串流時，他家拔北面恆 0，與訓練資料（全知牌譜）不一致。全知串流下兩者相同。
- 他家摸牌是 `?` 時 `drawnTile` 設 nil，不照 Rust 留 tid 0。Rust 在 Naki 這種串流下，搶槓與拔北榮和窗口的摸牌面會亮出假 1m（復驗以 seed126 seat0 事件 95 證實），與全知的訓練分布不一致。手牌仍照 Rust 補 tid 0。
- `ankan`／`kan` 的 consumed 為空時拒絕事件並回傳 false；否則後續以 `tiles[0]` 取槓子種類會越界 trap。
- 解析失敗的牌照 riichienv 當成 tid 0，所以他家 `?` 手牌會變成多張 1m，而且隨摸牌單調增長。`isAgari` 遇到單種超過 4 張直接判否，因為 MortalSwift 的 `ShantenTable` 以 unsafe 指標查表，會越界。這只影響他家的回應判定，不影響本家的決策。
- 事件欄位比 serde 寬鬆：只檢查狀態用得到的欄位（例如 `dahai` 不要求 `tsumogiri`、`pon` 不要求 `target`）。缺欄位或 actor 不在 0...2 時不套用並回傳 false，不會 crash。
- 授權閘除了捨牌，也永遠保留 pass，避免回應窗口被迫叫牌。`forced` 依閘後的動作數。
- 開局前（尚未 `start_kyoku`）沒有決策點。Rust 建構子的隨機牌局在 `start_game` 前可能有合法動作，那條路徑 Akagi 不會走。
- `SanmaEncInput.encode()` 改回傳 Optional：`seats` 不是正好 3 家時回 nil。`waits` 只接受 tile34 < 34。
- muter 16 無法直接用：(1) 含中文註解的檔案會算錯位移、產生壞掉的程式碼；(2) 大函式中多數 mutant 沒被插進 schemata，卻被報成「存活」；(3) Legal 單檔超過 10 分鐘。改用同運算子集合的手工 harness（`mutate.py`），結果在 Naki `.swfd/logs/s1b-sanma-state/mutation/`。

## 未驗證

- fixtures 全是全知牌譜（selfplay），沒有他家手牌為 `?` 的串流；`?` 相關行為只有手寫單測。
- fixtures 只有 seat 0、seat 1，沒有 seat 2；seat 2 的座位旋轉只有手寫單測。
- fixtures 沒有拔北榮和窗口。
- 變異測試只涵蓋 muter 的運算子集合（關係運算、邏輯連接詞、三元互換），外加復驗修正的三個分支。

## S1c 待辦（Naki 接線時處理）

- codex 審查第 2、3 節：伺服器 oplist 與實體 `SanmaAction` 的逐組合對應（碰／槓的 consumed 與赤五 copy、立直可宣言捨牌、pass 合成、搶槓 context）。本包只提供 `decide(authorized:)` 的類別閘，沒有做逐組合對應。

