# 決策紀錄：observation 編碼要不要恢復 libriichi

**日期**: 2026-08-01
**狀態**: 已完成。1012 格全部與 libriichi 逐格一致

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

用同一串 MJAI 事件同時餵 libriichi 與純 Swift，在**每一個需要動作的時點**比對：

| 階段 | obs 落差 | mask 落差 |
|------|---------|----------|
| 起點 | 82 / 1012 | 0 |
| 對齊前段佈局後 | 71 | 0 |
| 完整重寫佈局後 | 57 | 0 |
| 換上真的會動的一局測資後 | 6（已移植區段） | 1 |
| 補完役種判定（ch877） | 62 | 0 |
| 補完單人期望值表（ch889–1011） | **0** | **0** |
| **現況** | **0 / 1012 全部一致** | **0** |

**1012 格全部逐格一致，`knownUnportedChannels` 已清空。**
模型現在收到的每一格，語意都與它訓練時看到的相同。

> ⚠️ 先前曾用「非零 channel 數」估算落差，得出「只填了 23 個、其餘全空」——**那個推論是錯的**。
> libriichi 的 obs 本來就大部分是 0，用非零數估算會嚴重高估落差。
> 只有逐格對拍才是有效的量測。

## 測資本身也要驗

第一版測資只有三個事件（配牌 → 摸一張），對拍顯示「57 格不一致」，聽起來像只剩尾段沒做。
但那份測資**完全沒有碰到河、副露、手切、對家立直**——那些 channel 的「一致」，
其實只是「兩邊都是 0」。

換成走過三巡、含碰（會跳過一家）與他家立直的完整劇本後，立刻多冒出 6 個真實落差。
教訓與 channel 佈局那件事是同一個：**沒被執行到的路徑，測試不會告訴你它是錯的。**

另外替 oracle 加了拒收偵測。libriichi 對格式不符的事件會回 `RIICHI_ERROR`，
原本的包裝把它和「不需要動作」混在一起回 nil——那會讓 oracle 從某個事件起靜默停止更新，
而對拍照樣「通過」。這種假驗證比沒有驗證更危險。

## 修掉的落差

**佈局類**（前段多算或少算 channel，會把其後每一格都推移）：

1. **分數多了 3 格** — Swift 額外編了「相對分數差」；
   libriichi v4 每位玩家只有 100k 與 30k 兩格正規化。
2. **本場／立直棒的格數** — libriichi v4 的 `IntegerEncoder` **只做 rescale**，各佔 1 格。
   `rbf_intervals` 僅在 v2/v3 生效，**v4 分支完全忽略它**。
3. **風的編碼方式** — libriichi 用 `assign(該風的牌索引, 1.0)`，只在牌索引上打一點；
   原本寫成 4+4 格 one-hot，多佔 6 格。另補上遺漏的「場風×4+局數」合成 channel。
4. **局數的 base** — libriichi 的 `state.kyoku` 是 0-based（東1 = 0）。
5. **寶牌指示牌是 7 格的 tile set**（4 格計數 + 3 格紅五），原本只用 2 格。
6. **河的整段結構全錯** — 自家每項 4 格、對家每項 8 格，各有「開頭 6 項」與
   「結尾 18 項（由新到舊）」兩個視窗，之後還有時間衰減。原本的寫法格數與語意都對不上。
7. **中間整段缺席** — 各家持有寶牌數、未見寶牌數、河概覽、副露（每家 4 組 × 5 格）、
   暗槓、對家最後手切牌、對家立直宣言牌、各動作可用性，原本都沒有編。

**狀態機類**（佈局對了以後才浮出來的）：

8. **向聽剪枝漏算搭子** — 下界只樂觀估「剩下的牌還能湊幾組面子」，漏掉搭子。
   `1m1m 234m 567p 234s 5s6s` 明明打 5m 就聽 4s/7s，卻被算成一向聽。
   這不只影響 observation，還讓立直判定與打牌分類整組錯掉。
9. **假聽牌** — `1111m 333p 222s 444z` 形式上可拆成四面子 + 1m 單騎，
   但四枚 1m 都在手上，第五枚摸不到。面子分解本身不管牌還有沒有剩，
   要逐張試進才排除得掉。
10. **`shanten` 的生命週期** — libriichi 的 `shanten` **一律是 3n+1 手牌的值**，
    摸牌後不重算（tsumo handler 裡明寫 "Does not update shanten"）。
    Swift 每次摸牌都重算，使得 `nextShantenDiscards` 與 `canRiichi`
    這些「拿它當基準比較」的判斷全部失去意義。自摸判定也因此要改成
    「摸到的牌在 waits 裡」而不是「shanten == -1」。
11. **立直成立沒扣分** — 那 1000 點是從分數扣掉再變成場上的立直棒，
    只加 kyotaku 不扣分會讓分數這幾格一路錯到局末。
12. **`isDora` 的語意** — 指「這張牌本身是寶牌」（`doraFactor > 0`），
    不是「這張是寶牌指示牌」。
13. **`tiles_seen` 兩邊都漏** — 自己的起手牌要算已見（原本沒算），
    自己打出的牌不能再算一次（原本重覆計數），副露亮出來的牌要算（原本沒算）。
14. **吃碰槓掛錯位置** — libriichi 把副露資訊掛在**打牌者自己**的河項上
    （「我副露之後打出這張」），Swift 掛到被吃那家的河上。
    而且 `intermediateChiPon` 在每個事件開頭都被清空，等於永遠讀不到。
15. **河沒有輪次對齊** — 四家的河陣列要用 `nil` 補齊被跳過的輪次
    （開局在莊家之前的座位、以及碰／大明槓跳過的座位），
    否則時間衰減的基準在四家之間對不起來。

## 後續補完的部分

| Channel | 內容 | 移植自 |
|---------|------|-------|
| ch877 | 打了之後無條件聽牌且有役的候選 | `agari.rs`（役種與符計算） |
| ch889–1011 | 每張打牌在每一巡的聽牌率／和牌率／期望值 | `algo/sp`（期望值 DP） |

實作細節與偏離記錄見 [implementation-notes](implementation-notes.md)。

順帶修掉的：副露手的自摸判定先前只能樂觀當作「有役」，
現在用真正的役種判定。

## 方法論（本輪反覆確認的教訓）

**權威定義優先於推論。** 這一輪一開始是憑讀 code 猜 channel 語意，
換來的是錯誤的落差估計。改成把 libriichi 的原始碼取回來
（`docs/reference/libriichi_obs_repr.rs`，來源 `Equim-chan/Mortal`；
另取 `state/update.rs`、`algo/shanten.rs` 確認狀態機與向聽的語意）
逐段對照後，每一處修正都能立刻用對拍數字驗證。

同樣的模式在本輪出現多次：協定欄位該查 `liqi.json`、牌的螢幕位置該讀 shader uniform、
observation 佈局該讀 `obs_repr.rs`、`shanten` 何時該重算該讀 `update.rs`。判準是：
**動手算之前先問「產生這個資料的那一方有沒有留下來」。**

## 驗收標準

- `obsParityAgainstLibRiichi`：已移植區段 0 落差（**現況達成**）
- `maskParityAgainstLibRiichi`：0 落差（**現況達成**）
- `shantenAgainstLibRiichiCases`：libriichi 自己的 19 個案例全過（**現況達成**）
- 未移植的 124 格補完後，`knownUnportedChannels` 要清空
- 對拍測試永久保留，作為日後修改編碼器的回歸保護

---

## 補記（2026-08-02）：紅五劇本

原本的兩個劇本（`minimal` / `full`）**一張紅五都沒有**，所以 mask 34-36 兩邊
永遠都是 0——「對拍零落差」在紅五這一段其實什麼都沒驗到。
補了三個劇本（`aka-discard` / `aka-riichi` / `aka-meld`），並加一條
`akaScenariosActuallyExerciseAkaMask` 斷言 libriichi 自己真的在這些時點打開了
34-36，避免劇本退化成「兩邊都是 0」。

補完後立刻抓到兩個先前看不見的落差：

1. **ch722（未見寶牌數）** — `akasSeen` 只在有人**打出**紅五時才設。
   自己配牌／摸到的紅五不算「已見」，`doras_unseen` 因此多算一張；
   同一個旗標還被單人期望值推演拿去當 `akasInWall`，等於讓 DP 以為
   自己手上那張紅五還能再摸到一次。改成跟 `tilesSeen` 同一個入口
   （`markTileSeen`）標記——語意是「這張紅五已經現身」，不是「已經被打出」。

2. **ch15-18（順位）** — `rank` 只在開局算一次。立直成立扣掉 1000 點之後
   分數變了、順位沒變，四家同分時自己立直會從「暫定第一」掉到最後，
   obs 卻還停在第一。`handleReachAccepted` 補上 `updateRank()`。

兩者都與紅五本身無關，是紅五劇本走到了先前沒人走過的路徑才暴露出來的。
這正是「修規則 bug 前先補對應劇本」的理由。

## 補記（2026-08-02）：振聽劇本

原本七個劇本**一次榮和機會都沒有**，所以 ch861（振聽）與 mask[43]（榮）兩邊
永遠都是 0——跟紅五那次一樣，「零落差」在振聽這一段什麼都沒驗到。
補了六個劇本（`furiten-miss` / `furiten-miss-then-tsumo` / `furiten-riichi` /
`furiten-discard` / `furiten-no-yaku` / `furiten-meld`），並加一條
`furitenScenariosActuallyExerciseFuritenChannel` 斷言**每一條**劇本都真的走進過振聽、
而且劇本群裡出現過「振聽擋掉榮和」的形狀。

用 xcframework 逐事件對拍後，libriichi 的振聽語意是這樣（全部是量出來的，不是讀碼猜的）：

| 情境 | ch861 何時變 1 | 何時變回 0 |
|------|---------------|-----------|
| 見逃（這張榮得了但沒榮） | **下一個事件**才變 1（被問要不要榮的那一格是 0） | 自家**打牌**後（自家摸牌不解除） |
| 待牌流過但無役榮不了 | 待牌流過的**當下**就變 1 | 同上 |
| 自己打過待牌（捨牌振聽） | 自家打牌後重算時 | 聽牌改變且新待牌都沒打過時 |
| 立直成立後見逃 | 同見逃 | **永不解除** |

實作對應：`pendingSameCycleFuriten`（libriichi 的 `to_mark_same_cycle_furiten`）
在 `update()` 開頭 take；`updateFuriten()` 改成每次自家打牌重算，立直時只增不減。
原本 `updateFuriten()` 只會寫 `true`、局內沒有任何路徑寫回 `false`，
見逃一次之後整局的榮和就被鎖死。

補完後同樣抓到兩個與振聽無關、只是先前沒人走過那條路的落差：

1. **榮和沒有役判定** — `canRon` 只看「在 waits 裡且不振聽」。門前**不是**役
   （門前清自摸和只算自摸），無役聽牌 libriichi 的 mask[43] 是 0。
   補上 `AgariCalculator(isRon: true).hasYaku()`（立直／河底走捷徑）。
2. **自家副露的 tiles_seen 重覆計數（ch835）** — 吃／碰／槓把 `consumed` 一律當成
   「新亮出來的牌」標記已見，但那是**自己手上**的牌，配牌／摸牌時就算過了。
   先前的劇本沒有任何一次自家副露，所以看不到。連帶讓 ch889–1011 的單人期望值
   整段偏掉（牌山剩餘張數算錯）——修掉 ch835 之後那 33 格自動歸零。

### 這一輪仍未修的已知缺口

**單人期望值表（`algo/sp`）還原不完整**，兩處實測落差，都與振聽無關：

1. **SP 算不出來時的 fallback** — libriichi 在 `single_player_tables()` 回 `Err` 時，
   會改用「最小自摸和了點數」當期望值填 ch889/890（`obs_repr.rs:612-623`）；
   純 Swift 那兩格留 0。自摸到自己的待牌（含天和／地和）就會走到。
   要補完得先有和了點數與天和／地和的加飜。
2. **ch959「進張數最多的打牌」的並列規則** — libriichi 用
   `max_by(|l, r| l.cmp(r, NotShantenDown))`，`Candidate::cmp` 的次要排序鍵
   不在 `docs/reference/` 裡。實測三個並列局面：兩個取第一個、一個取第二個，
   單純改成「取最後一個」反而讓 minimal / aka-discard 對不上。維持取第一個。

兩者都需要把 libriichi 的 `algo/sp` 取回來逐段對照才做得完，
**不要靠黑箱猜**——這一輪已經驗證過猜的代價。
現有劇本刻意繞開這兩條路徑（見 `furitenDiscardEvents` 的註解），
所以對拍仍是零落差；但那是「沒踩到」，不是「已經對」。

### 先前那一輪仍未修的已知缺口

`aka-riichi` 劇本會走到自家 `reach` 事件。MJAI 在你宣告立直之後還會要你打一張，
libriichi 因此回 `ACTION_REQUIRED`，純 Swift 的 `update` 對自家宣告事件
（reach／chi／pon／kan）一律回 `false`——打牌是由呼叫端另外驅動的
（`inferCurrentState()`）。對拍工具裡用 `isSelfDeclaration()` 明確跳過這一類時點，
**不是**當成一致，而是標記成已知缺口；修那個缺口時把該分支拔掉，對拍會立刻抓回來。
