# 加槓紅五：consumed 取自原碰、pai 取自手上那張

**日期**: 2026-08-06
**狀態**: 已修，兩個回歸測試鎖住（`AkaDoraDecodeTests`）；順帶把四份 consumed 產生器合一

---

## Bug（clean code 掃描期間發現，測試證實）

`ActionDecoder.getKakanConsumed` 原本註釋寫「簡化處理：返回三張一樣的牌」，
兩個半邊都錯：

1. **consumed**：原碰含紅五時（碰 `[5mr,5m]`＋叫牌 `5m`），加槓的 consumed
   應是原碰那三張 `{5mr,5m,5m}`，卻回三張普通 `5m`。
2. **pai**：紅五還在手上時（碰的是三張普通五），加槓宣告的第四張就是紅五，
   卻宣告普通 `5m`。這一半更危險——`handleKakan` 對自家做
   `removeTile(event.pai)`，移錯牌會留下 `akasInHand` 幽靈旗標，
   之後的 observation 紅五通道全錯。

## 為什麼這樣修（取捨）

- **consumed 從 `fuuroOverview[0]` 查原碰牌組**，不從現在的手牌重算：
  含不含紅五是「碰當下」的事實，事後手牌推不回來。比對條件
  `count == 3 && 全部同 deaka index` 唯一命中碰面子（吃是異索引、
  大明槓是 4 張）。
- **pai 看 `akasInHand`**：加槓時手上該索引最多剩 1 張（4 張中碰用掉 3），
  旗標亮著那張就是紅五，不需要額外狀態。
- **四份 consumed 產生器合一**成 `consumedTiles(tile:count:state:)`
  （碰 2／大明槓 3／暗槓 4）：三份已開始漂移（碰有張數守衛、兩個槓沒有），
  統一守衛 `tehai[idx] >= count` 在合法 mask 下行為不變、非法呼叫下更嚴。
  紅五三元組 `(4,0)/(13,1)/(22,2)` 同時收成一張表，原本手寫散在 6 處。
- 加槓刻意**不**併入 `consumedTiles`：它的資料來源是副露狀態不是手牌，
  硬併會把兩種語意壓進同一個函式。

## 驗證

`swift test` 全套 69 tests 通過（含新增
`kakanConsumedKeepsAkaFromOriginalPon` / `kakanPaiIsAkaWhenAkaStillInHand`）。
未做 live 對局驗證（加槓紅五的局面罕見，靠 replay/單測鎖）。

## 對 Naki 的影響

Naki 由已提交的 `Package.resolved` 釘在 0.5.2/`6223548`；本修正要等
MortalSwift commit＋打新 tag＋Naki bump 後才會生效。在那之前 Naki 的
加槓推薦顯示（與任何 MJAI 事件流消費端）仍帶舊行為。
