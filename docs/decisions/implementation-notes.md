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

---

## 進度

- [x] Point（點數換算）— 用 libriichi 自己測試證明過的通式取代 40 行對照表
- [x] 手牌拆解列舉（取代 AGARI_TABLE）
- [x] 符計算 `calc_fu`
- [x] 役種判定 `search_yakus` — libriichi 全部 24 個案例通過
- [x] **ch877 對拍歸零**（剩餘落差 62，全在 ch889–1011）
- [ ] sp: state / candidate
- [ ] sp: calc（期望值 DP）
- [ ] ch889–1011 對拍歸零

### D2. `hasIpeikou` 只在 4 面子（門前 14 張）時成立

**原始**: 表裡的 `has_ipeikou` 由建表程式決定，原始碼註解只說
「sound but not complete, broken if there is any ankan」。

**偏離**: 反推出的規則是「面子數 == 4 才設」，並照此實作。

**為什麼保守**: 牌數不足 14 代表有副露，而一盃口要求門前——
設了就是誤判。少設只會漏掉「有暗槓但仍門前」那種情形，
而 `searchYakus` 本來就有補救路徑處理它。**寧可漏判不可誤判。**

**驗證**: libriichi 測試裡三個相關案例（無副露 / 有副露 / 有暗槓）全部通過，
證明這條規則與原始表的行為一致。

---

## 未解問題

（目前無）
