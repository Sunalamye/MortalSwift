# 模型來源、鑑定方法與三麻現況

**日期**: 2026-08-01
**狀態**: 調查結論；三麻因缺權重未實作

---

## 為什麼要寫這份

模型檔沒有版本控管、沒有 metadata 可信任、來源是 Discord 上陌生人打包的壓縮檔。
「這份是三麻還是四麻」「這份能不能續訓」這種問題，**每次都得重新查**——
除非把判準寫下來。這份文件就是那組判準。

## 權重的取得管道

Mortal 的**訓練權重不在任何公開 repo**：

- 上游 `Equim-chan/Mortal` 只有程式碼
- Akagi 的 README 明寫：「A `mortal.pth`. (Get one from Discord server if you don't have one.)」
  → https://discord.gg/Z2wjXUK8bN，流程是 #verify 點 ✅ → #bot-zip 下載
- MahjongCopilot 把使用者導回 Akagi 拿模型
- HuggingFace 上沒有（`mortal` / `mahjong` / `riichi` / `sanma` 全搜過，只有影像辨識類）

`MortalSwift/Sources/MortalSwift/Resources/mortal.mlmodelc` 就是從這條管道拿到的
`.pth` 轉出來的。

## 鑑定判準（不要看檔名）

檔名不可信——三麻四麻可能同樣叫 `mortal.pth`，靠所在資料夾區分。**只看維度**：

| 判準 | 四麻 | 三麻 |
|------|------|------|
| 第一層 conv 的輸入通道 | **1012** | **775** |
| ACTION_SPACE（DQN 輸出） | 46 | 44 |
| `config.env.pts` | 四項 | 三項 |

第三項特別好用：三麻只有三個名次，`pts` 陣列不可能是四項。
兩個獨立證據同時指向同一邊才下結論。

檢查腳本：`docs/reference/inspect_pth.py`。用法：

```
proto run python -- inspect_pth.py <某個.pth>
```

### 安全性：不要用 `torch.load` 檢查來路不明的檔案

`.pth` 是 zip + pickle，**pickle 在反序列化時可以執行任意程式碼**。
那些 zip 裡除了 `.pth` 還有 `bot.py`、`model.py` 和 Linux 的 `libriichi.so`。

`inspect_pth.py` 用 `find_class` 白名單：只放行 torch 的 rebuild 符號與
stdlib 的 `codecs.encode`，其餘 torch/numpy 符號換成惰性 stub，非白名單直接拒絕。
全程沒有任何來自檔案的程式碼被執行，也不需要安裝 torch。

## 已鑑定的檔案（2026-08-01）

來自 Akagi Discord，**四份全是四麻**：

| 檔案 | 網路規模 | obs | 可續訓 | 備註 |
|------|---------|-----|--------|------|
| `bot_20240110_best.pth` | 192×40 | 1012 | ✅ | 150,000 步，avg_rank 2.5274 / avg_pt -2.034 |
| `bot_20240110_mortal.pth` | 192×40 | 1012 | ✅ | 90,000 步，avg_rank 2.5279 / avg_pt -3.0555 |
| `model_v4_20240308_best_min.pth` | 256×54 | 1012 | ❌ | metadata 全被剝除 |
| `model_v4_20240308_mortal_min.pth` | 256×54 | 1012 | ❌ | 同上 |

**目前內建的 `mortal.mlmodelc` 是 192×40 / fp16 / 21MB**——這是從 `model.mil` 的
權重形狀讀出來的事實（`[192, 1012, 3]` 輸入層 + 80 個 `[192, 192, 3]` = 40 個殘差塊），
不是從檔案大小推測的。

### `min` 與 `best` 是正交的兩件事

常見誤解。這兩個字描述不同維度：

- `best` vs `mortal` — **哪一個快照**。`best` = 評測最好的那次，`mortal` = 訓練當下最新
- `_min` — **有沒有精簡**。只留推論用的權重，砍掉 optimizer / scheduler / scaler / steps

所以 `best_min` 是合法組合。**推論用 `_min` 即可；但 `_min` 不能續訓**——
optimizer 動量與 LR 排程都沒了。

> ⚠️ `avg_rank` 那組數字要小心解讀。四麻的平均順位天生就是 2.5，
> 所以 2.5274 這種貼著 2.5 的值只代表評測對手與自己同強（自我對弈），
> **不代表模型弱**。有區別度的是 `avg_pt`。跨組（不同架構）比較這些數字沒有意義，
> 因為評測設定未知。

## 更大的模型會更好嗎——未驗證

256×54 比 192×40 參數多 2.4 倍（約 22.5M vs 9.5M），
轉成 Core ML 推估 45–48MB（現為 21MB），推論計算量約 2.4 倍。

**但沒有任何證據支持它更好**：兩份 `_min` 的 `config` 只剩
`{control: {version: 4}, resnet: {...}}`，訓練步數與評測分數全被剝除。

大不等於好——關鍵是訓練得夠不夠。同一份資料裡就有反例：
`bot_20240110` 那組架構完全相同，只因步數不同（15 萬 vs 9 萬），
`avg_pt` 就差了 1.0。

可量測的是：轉出後的大小、推論延遲、兩者推薦的分歧率。
**不可量測的是「哪個打得比較好」**——那需要跑幾千局的評測環境。
在那之前，「換了會更好」是先驗推測，不是量測結果。

## 三麻：引擎開源，權重不開源

### 引擎（可用）

`Mateces/mortal-sanma`（AGPL-3.0）是 libriichi 的三麻 fork：

| 項目 | 四麻 | 三麻 |
|------|------|------|
| obs_shape | (1012, 34) | **(775, 34)** |
| ACTION_SPACE | 46 | **44** |
| 牌山 | 136 張 | 108 張（無 2–8m） |
| 紅寶牌 | 5mr/5pr/5sr | 5pr/5sr |
| 吃 | 有 | **禁用** |
| 拔北 | 無 | Nukidora 事件 |
| 半莊 | 8 局 | 6 局 |

宣稱已用 200 條天鳳三麻鳳凰桌牌譜（1832 局）驗證。
**它可以當三麻版的 oracle**——跟四麻用 libriichi 逐格對拍是同一套手法。

### 權重（沒有）

搜過 HuggingFace、GitHub releases、上游 repo，都沒有三麻權重。
只能走 Akagi Discord。

### 相關線索

HuggingFace 的 `ffzeroHua/tenhou-scc`（99,972 檔，2026-08-01 仍在更新）
內容是 `{paipu, result: [{actions, masks, q_out}]}`——**Mortal 的三麻推論輸出**
（mask 長度 44、lobby code 一律 `00b9`），不是牌譜也不是權重。
但代表有人正在跑三麻模型，上傳者可能是取得權重的線索。

### 在拿到權重之前：不要假裝支援

`is3P` 目前只是個標籤，實際推論用的是四麻模型。三麻的 observation 佈局與
action space 都不同，拿四麻模型推三麻**不是「稍微偏差」而是結構上無效**。

因此 UI 不得標示 "Mortal (3P)"（那會讓人以為有專用模型），
改為 `Mortal (4P) ⚠️ 三麻無專用模型`。程式碼裡原本就有註解承認這件事，
但那只寫在原始碼，看畫面的人看不到。

## 續訓四麻的門檻

從 `bot_20240110_best.pth` 挖出的完整訓練設定可還原成 `config.toml`：
學習率 1e-4 恆定、weight_decay 0.1、batch 2560、CQL `min_q_weight=5`、
輔助任務 `next_rank_weight=0.16`、BN momentum 0.01 / eps 1e-3。

但有兩個硬門檻：

1. **GPU** — 官方 build 文件寫明訓練需要 GPU，config 是 `device: cuda:0` +
   `enable_cudnn_benchmark`，是 NVIDIA 專用路徑。macOS 走不通，得租 Linux GPU 機器。
2. **資料集** — 需要 `/mortal/dataset/{2019..2023}/*.json.gz`，
   即五年份的天鳳鳳凰桌牌譜轉成 MJAI 格式，外加頂尖玩家名單做過濾。
   `libriichi/src/bin` 只有 `stat.rs` 與 `validate_logs.rs`，
   **沒有內建的天鳳→MJAI 轉換器**。

### 資料集實際上拿不到（2026-08-01 實測）

**天鳳已不再提供歷史打包檔。** `scraw{2019..2025}.zip` 全部 404。
`https://tenhou.net/sc/raw/list.cgi` 只列出**約 8 天**的滾動資料
（`scc20260725`–`scc20260801`，鳳凰卓日檔壓縮後合計 0.3 MB）。
Mortal 訓練用的是**五年份**——差了三個數量級。

**而且天鳳的條款明文禁止這個用途**（`https://tenhou.net/sc/raw/` 頁面）：

> ※天鳳と競合する製品への開発・応用を目的として牌譜を使用していただくことはできません。
>
> ※天鳳の牌譜は、天鳳での対戦を公正に楽しんでいただく目的で公開されています。
> **天鳳での対戦を必要としないサービスへの応用は無償有償ともに行えません。**
> 一般の麻雀への応用を目的に牌譜を使用する場合は support@c-egg.com までお問い合わせください。
>
> ※不特定多数が天鳳の牌譜をダウンロードするサービスは作成できません。

Naki 是雀魂的輔助工具，屬於「不需要在天鳳對戰的服務」，
落在明確禁止的範圍內。要合法使用需先聯繫 `support@c-egg.com`。

**結論：續訓四麻在資料端就走不通**——不是難，是拿不到，而且拿到也不該那樣用。

還有第三件常被忽略的：訓練完之後要怎麼知道變好了？那需要另一套評測環境。

> **投資報酬率的判斷**：若目標是「讓推薦變好」，補完
> [obs-parity](obs-parity.md) 剩下的 124 格（單人期望值表與役種判定）
> 應該優先於換模型或續訓。現在模型連「每張打牌的期望值」都收不到，
> 那是**輸入端的資訊缺口**，不是模型容量不夠。
> 補那個不需要 GPU、不需要資料集，而且有 libriichi 當 oracle 可以逐格驗證。
