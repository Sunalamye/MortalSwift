# 補完 observation 剩餘 124 格：實作筆記

**開始**: 2026-08-01
**目標**: `obsParityAgainstLibRiichi` 的 `knownUnportedChannels` 清空
**範圍**: ch877（無條件聽牌且有役的打牌候選）、ch889–1011（單人期望值表）

---

## 為什麼需要這 124 格

模型是帶著這些資訊訓練的。現在 Naki 送全 0 過去，等於告訴模型
「每張牌打下去都沒有和牌希望」。模型不會崩潰（前面 888 格是對的），
但它在缺一大塊資訊的情況下硬推，而那塊恰好最直接關於「打哪張比較好」。

## 權威來源

| 檔案 | 行數 | 用途 |
|------|------|------|
| `libriichi/src/algo/agari.rs` | 1380 | 役種判定、符計算 |
| `libriichi/src/algo/point.rs` | 154 | 點數換算 |
| `libriichi/src/algo/sp/calc.rs` | 1008 | 單人期望值推演 |
| `libriichi/src/algo/sp/state.rs` | 206 | 推演用的手牌狀態 |
| `libriichi/src/algo/sp/candidate.rs` | 182 | 每張打牌的結果 |
| `libriichi/src/algo/sp/mod.rs` | 47 | 對外介面 |

全部取自 `Equim-chan/Mortal` main 分支，快取在 scratchpad。

## 驗收方式

跟前一輪（obs 佈局對齊）完全相同：libriichi 的 xcframework 已掛在 test target，
每完成一段就跑對拍，看對應 channel 是否歸零。**不靠讀 code 判斷對錯。**

---

## Deviations

> 偏離原始實作的地方。原則：**選保守選項**——寧可少宣稱、不要多宣稱。

### D1. 不移植 `agari.bin.gz` 查表，改為執行期列舉

**原始**: `AGARI_TABLE` 是 9,362 筆的 boomphf 完美雜湊表，
由 `data/agari.bin.gz` 載入，key 是手牌形狀的位元打包，
value 是所有可能的「4 面子 + 1 雀頭」拆法（含 chitoi / chuuren / ittsuu /
ryanpeikou / ipeikou 旗標）。

**偏離**: 改為在 Swift 端直接遞迴列舉拆法，不讀那個二進位檔。

**為什麼保守**: boomphf 的序列化格式沒有規格文件，要在 Swift 重現讀取邏輯
只能靠逆向，**錯了不會報錯只會靜默給錯的拆法**。直接列舉的正確性
可以用對拍驗證，而且不引入無法驗證的二進位相依。

**代價**: 每次查詢都要重算（原本是查表）。和牌判定不在每幀路徑上，
但單人期望值推演會大量呼叫——若實測太慢，再加 memo cache。

### D2. `hasIpeikou` 只在 4 面子（門前 14 張）時成立

**原始**: 表裡的 `has_ipeikou` 由建表程式決定，原始碼註解只說
「sound but not complete, broken if there is any ankan」。

**偏離**: 反推出的規則是「面子數 == 4 才設」，並照此實作。

**為什麼保守**: 牌數不足 14 代表有副露，而一盃口要求門前——
設了就是誤判。少設只會漏掉「有暗槓但仍門前」那種情形，
而 `searchYakus` 本來就有補救路徑處理它。**寧可漏判不可誤判。**

**驗證**: libriichi 測試裡三個相關案例（無副露 / 有副露 / 有暗槓）全部通過，
證明這條規則與原始表的行為一致。

### D3. 向聽改用 libriichi 的查表，並保留遞迴版當對照

**原始**: `algo/shanten.rs` 用兩張預先算好的表
（`shanten_suhai.bin.gz` 1,940,777 列、`shanten_jihai.bin.gz` 78,032 列）。

**先前**: Swift 版是自己寫的遞迴分解，正確但慢。

**改動**: 移植查表版，表載入失敗時退回遞迴版。

**為什麼不算違反 D1**: 這兩張表的格式在 libriichi 原始碼裡**完整寫著**
（`read_table` 的 nibble 拆法、`sum_tiles` 的 5 進位索引、`add_suhai`/`add_jihai`
的合併規則），不需要逆向任何東西——與 boomphf 的情況完全不同。
而且遞迴版留著當測試對照組，3000 手隨機牌逐一比對，兩者不一致就會被抓到。

**為什麼非做不可**: 期望值推演會呼叫向聽計算數百萬次。
實測開局三向聽的一次 observation 編碼要 **75.6 秒**——那不是慢，是不能用。
換成查表後降到 **1.2 秒**。

---

## 進度

- [x] Point（點數換算）— 用 libriichi 自己測試證明過的通式取代 40 行對照表
- [x] 手牌拆解列舉（取代 AGARI_TABLE）
- [x] 符計算 `calc_fu`
- [x] 役種判定 `search_yakus` — libriichi 全部 24 個案例通過
- [x] **ch877 對拍歸零**（剩餘落差 62，全在 ch889–1011）
- [x] sp: state / candidate
- [x] sp: calc（期望值 DP）
- [x] **ch889–1011 對拍歸零**
- [x] 向聽改查表（75.6 秒 → 1.2 秒）

### 完成

**1012 格全部與 libriichi 逐格一致，落差 0。**
`knownUnportedChannels` 已清空，46 個測試全過。

| 情境 | Debug | **Release** |
|------|-------|------------|
| 聽牌（剩 60 張） | 3.6 ms | **0.1 ms** |
| 開局三向聽（剩 69 張，最壞） | 1,225 ms | **36.7 ms** |

---

### D4. 向聽表攤平成連續緩衝區

原本存成 `[[UInt8]]`——194 萬個獨立的堆積配置陣列，每次查詢都是指標追逐
加 retain/release。改成單一 `[UInt8]` 以算術索引，並用
`withUnsafeTemporaryAllocation` 把工作緩衝放在堆疊上，全程零堆積配置。

---

## 效能：量測配置的陷阱

**`swift test` 預設是 debug build。** 我一開始拿 debug 的數字判斷效能，
得到「最壞情況 1.2 秒」的結論，並據此考慮要不要改演算法。

用 `swift test -c release` 重量之後：

| 元件 | Debug | Release | 倍數 |
|------|-------|---------|------|
| 向聽查表 | 14,266 ns | 77 ns | 185× |
| `drawTiles`（34 次向聽） | 333,088 ns | 4,579 ns | 73× |
| 最壞情況編碼 | 1,225 ms | **36.7 ms** | 33× |

**36.7 ms 完全不需要再優化。** 之前列的那些方向（位元打包狀態、換雜湊、
降低向聽門檻）現在都沒有必要，也就沒有做——省下的是「為了不存在的問題
增加的複雜度」。

⚠️ 但有一個實際影響：**Naki 目前是用 Debug 建置在跑的**
（`xcodebuild build` 不加 `-configuration Release`），
所以使用者實際體驗到的是 1.2 秒那一版。要拿到 36.7 ms 需要用 Release 建置。

## 未解問題

（目前無）
