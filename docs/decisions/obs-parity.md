# 決策紀錄：observation 編碼要不要恢復 libriichi

**日期**: 2026-08-01
**狀態**: 已定案（選 B），實作進行中

---

## 背景

`mortal.mlmodelc` 是**固定成品**（由 `mortal.pth` 轉出），它的輸入是
`obs: 1012 × 34` 與 `mask: 46`。每一個 channel 代表什麼，完全由
libriichi（Mortal 專案的 Rust 核心）的編碼決定——**模型與 libriichi 是一組的**。

v0.3.0（commit `e208621`）為了避開 Rust 工具鏈與靜態庫閃退，
把 `libriichi.xcframework` 從 `Package.swift` 移除，改用手寫的純 Swift
（`PlayerState` / `StateUpdate` / `ObsEncoder` / `ActionDecoder`，約 2000 行）。

**但那次替換沒有做過任何逐 channel 的等價驗證。** 換掉編碼器等於換掉模型的語言，
而驗收方式只有「跑得動、有輸出推薦」——那證明不了語意正確。

## 決策

| 方案 | 內容 | 取捨 |
|------|------|------|
| A | 把 `libriichi.xcframework` 掛回產品 target | 最短路徑回到正確語意；但推翻 v0.3.0「純 Swift 無 FFI」的方向，且原本的閃退風險未經重現確認 |
| **B（採用）** | 補完純 Swift 編碼器，以 libriichi 為基準逐 channel 對拍 | 保留純 Swift 方向；工作量較大，但有 oracle 可驗證，做完就有永久的回歸保護 |
| C | 維持現狀 | 否決——等於 AI 是瞎的 |

**選 B 的附帶決定：libriichi 只掛在 test target。**
產品 target `MortalSwift` 仍然零 Rust 依賴，發布出去的 library 不含那個 102MB binary；
xcframework 純粹當對拍基準。這樣既拿到 oracle，又不放棄 v0.3.0 的方向。

> B 若沒有 A 當 oracle 是做不了的——「補完 989 個 channel」無從驗證對錯。
> 所以實際上是「用 A 的機制驗收 B 的成果」。

## 量化落差（實測，非推論）

用同一串 MJAI 事件同時餵 libriichi 與純 Swift，取「輪到自己打牌」那一刻比對：

| 項目 | 結果 |
|------|------|
| mask（46 格） | **完全一致** |
| obs（1012 channel） | 初測 **82 個不一致** |

> ⚠️ 先前曾用「非零 channel 數」估算落差，得出「只填了 23 個、其餘全空」——**那個推論是錯的**。
> libriichi 的 obs 本來就大部分是 0，用非零數估算會嚴重高估落差。
> 只有逐格對拍才是有效的量測。

## 落差的性質：佈局錯位，不是缺段

前段多算幾個 channel，會把後面**每一格**都往後推，
於是模型收到的每一格語意都跟訓練時不同。所以修正必須從最前面開始逐段對齊。

已修正（前 28 個 channel 現已完全一致，落差 82 → 71）：

1. **分數多了 3 格** — Swift 額外編了「相對分數差」；
   libriichi v4 每位玩家只有 100k 與 30k 兩格正規化。
2. **本場／立直棒的格數** — libriichi v4 的 `IntegerEncoder` **只做 rescale**，各佔 1 格。
   `rbf_intervals` 僅在 v2/v3 生效，**v4 分支完全忽略它**。
3. **風的編碼方式** — libriichi 用 `assign(該風的牌索引, 1.0)`，只在牌索引上打一點；
   原本寫成 4+4 格 one-hot，多佔 6 格。另補上遺漏的「場風×4+局數」合成 channel。
4. **局數的 base** — libriichi 的 `state.kyoku` 是 0-based（東1 = 0），
   而這裡直接取 MJAI 的 1-based 值。

剩餘 71 個集中在三處：
`ch209-215`（自家河位移）、`ch717-910`（對家河與副露，libriichi 有值而 Swift 全空）、
`ch959-1011`（連續 53 格，對應 `ObsEncoder` 結尾那個只加計數器、不寫任何值的空迴圈）。

## 方法論（本輪反覆確認的教訓）

**權威定義優先於推論。** 這一輪一開始是憑讀 code 猜 channel 語意，
換來的是錯誤的落差估計。改成把 libriichi 的原始碼取回來
（`docs/reference/libriichi_obs_repr.rs`，來源 `Equim-chan/Mortal`）
逐段對照後，每一處修正都能立刻用對拍數字驗證。

同樣的模式在本輪出現多次：協定欄位該查 `liqi.json`、牌的螢幕位置該讀 shader uniform、
observation 佈局該讀 `obs_repr.rs`。判準是：
**動手算之前先問「產生這個資料的那一方有沒有留下來」。**

## 驗收標準

- `obsParityAgainstLibRiichi` 必須全綠（0 個 channel 不一致）才算完成
- 在此之前，**Bot 的推薦品質不可當真**——輸入語意仍有錯
- 對拍測試永久保留，作為日後修改編碼器的回歸保護
