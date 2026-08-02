//
//  ObsParityTests.swift
//  MortalSwiftTests
//
//  純 Swift 編碼器 vs libriichi 的逐 channel 對拍。
//
//  為什麼需要這個：`mortal.mlmodelc` 是固定成品，它訓練時看到的 1012 個 channel
//  各自代表什麼，完全由 libriichi 的編碼決定。純 Swift 版要接管推論，
//  唯一能證明語意一致的方式就是拿 libriichi 當基準逐格比對——
//  不能靠讀 code 推論，也不能靠「看起來有推薦」判斷。
//
//  libriichi 只在測試裡連結（見 Package.swift），產品 target 仍是純 Swift。
//

import CLibRiichi
import CoreML
import Foundation
import Testing

@testable import MortalSwift

// MARK: - libriichi oracle 封裝

/// 把 MJAI 事件餵給 libriichi，取得它產生的 observation 與 mask
final class LibRiichiOracle {
    private let bot: OpaquePointer
    let channels: Int
    let width: Int

    init?(playerId: UInt8, version: UInt32 = 4) {
        guard let handle = riichi_bot_new(playerId, version) else { return nil }
        bot = handle
        var ch = 0, w = 0
        riichi_obs_shape(version, &ch, &w)
        channels = ch
        width = w
    }

    deinit {
        riichi_bot_free(bot)
    }

    /// libriichi 是否拒收過任何事件。一旦發生，之後的比對全部沒有意義。
    private(set) var rejected: [String] = []

    /// 餵一個 MJAI 事件；需要動作時回傳 (obs, mask)，否則 nil
    func update(_ mjaiJSON: String) -> (obs: [Float], mask: [Bool])? {
        var obs = [Float](repeating: 0, count: channels * width)
        var mask = [UInt8](repeating: 0, count: 46)

        let result = mjaiJSON.withCString { cstr in
            obs.withUnsafeMutableBufferPointer { obsBuf in
                mask.withUnsafeMutableBufferPointer { maskBuf in
                    riichi_bot_update(bot, cstr, obsBuf.baseAddress, maskBuf.baseAddress)
                }
            }
        }

        if result == RIICHI_ERROR {
            rejected.append(mjaiJSON)
            return nil
        }
        guard result == RIICHI_ACTION_REQUIRED else { return nil }
        return (obs, mask.map { $0 != 0 })
    }
}

// MARK: - 測試劇本

/// 最小劇本：配牌後立刻輪到自己打牌
private let minimalEvents: [String] = [
    #"{"type":"start_game","id":0,"names":["A","B","C","D"]}"#,
    #"{"type":"start_kyoku","bakaze":"E","dora_marker":"E","kyoku":1,"honba":0,"kyotaku":0,"oya":0,"scores":[25000,25000,25000,25000],"tehais":[["1m","2m","3m","4m","5m","6m","7m","8m","9m","1p","1p","1p","2s"],["?","?","?","?","?","?","?","?","?","?","?","?","?"],["?","?","?","?","?","?","?","?","?","?","?","?","?"],["?","?","?","?","?","?","?","?","?","?","?","?","?"]]}"#,
    #"{"type":"tsumo","actor":0,"pai":"5p"}"#,
]

/// 完整劇本：非莊家視角，走過數巡，含手切／摸切、他家立直、碰（會跳過一家）。
///
/// 這些是最小劇本完全碰不到的區段——河的輪次對齊、副露、手切旗標、對家立直宣言牌。
/// 沒有這段，「channel 一致」多半只是「兩邊都是 0」。
private let fullEvents: [String] = [
    #"{"type":"start_game","id":0,"names":["A","B","C","D"]}"#,
    // 莊家是 seat 2 → 自己（seat 0）在第一巡之前要補兩個輪次佔位
    #"{"type":"start_kyoku","bakaze":"E","dora_marker":"3s","kyoku":3,"honba":1,"kyotaku":1,"oya":2,"scores":[24000,31000,22000,23000],"tehais":[["1m","1m","2m","3m","4m","5p","6p","7p","2s","3s","4s","E","C"],["?","?","?","?","?","?","?","?","?","?","?","?","?"],["?","?","?","?","?","?","?","?","?","?","?","?","?"],["?","?","?","?","?","?","?","?","?","?","?","?","?"]]}"#,

    // 第 1 巡：莊家 seat2 起
    #"{"type":"tsumo","actor":2,"pai":"?"}"#,
    #"{"type":"dahai","actor":2,"pai":"9p","tsumogiri":true}"#,
    #"{"type":"tsumo","actor":3,"pai":"?"}"#,
    #"{"type":"dahai","actor":3,"pai":"E","tsumogiri":false}"#,
    #"{"type":"tsumo","actor":0,"pai":"5m"}"#,
    #"{"type":"dahai","actor":0,"pai":"C","tsumogiri":false}"#,
    #"{"type":"tsumo","actor":1,"pai":"?"}"#,
    #"{"type":"dahai","actor":1,"pai":"9s","tsumogiri":true}"#,

    // 第 2 巡
    #"{"type":"tsumo","actor":2,"pai":"?"}"#,
    #"{"type":"dahai","actor":2,"pai":"8p","tsumogiri":false}"#,
    #"{"type":"tsumo","actor":3,"pai":"?"}"#,
    #"{"type":"dahai","actor":3,"pai":"W","tsumogiri":true}"#,
    #"{"type":"tsumo","actor":0,"pai":"5s"}"#,
    #"{"type":"dahai","actor":0,"pai":"E","tsumogiri":false}"#,

    // seat2 碰掉 seat1 的牌之前，先讓 seat1 打出來；碰會跳過 seat3
    #"{"type":"tsumo","actor":1,"pai":"?"}"#,
    #"{"type":"dahai","actor":1,"pai":"F","tsumogiri":false}"#,
    #"{"type":"pon","actor":2,"target":1,"pai":"F","consumed":["F","F"]}"#,
    #"{"type":"dahai","actor":2,"pai":"1s","tsumogiri":false}"#,

    // 第 3 巡：seat3 立直
    #"{"type":"tsumo","actor":3,"pai":"?"}"#,
    #"{"type":"reach","actor":3}"#,
    #"{"type":"dahai","actor":3,"pai":"N","tsumogiri":false}"#,
    #"{"type":"reach_accepted","actor":3}"#,

    // 輪到自己
    #"{"type":"tsumo","actor":0,"pai":"6s"}"#,
]

/// 紅五劇本 A：手上唯一的五是紅五 → 普通五那格 mask=0、紅五格 mask=1
///
/// `applyAkaToCandidates` 規定：手上只有一張五且是紅五時，普通五那格關掉、
/// 紅五那格打開。這正是 `ActionDecoder` 少了 34-36 分支時會停手的局面，
/// 所以對拍劇本一定要走到這裡，否則 mask 34-36 永遠是 0，等於沒驗。
///
/// 第二段（摸 5pr 時手上已有普通 5p）則驗另一半：兩張都在手上時 13 與 35 都要是 1。
private let akaDiscardEvents: [String] = [
    #"{"type":"start_game","id":0,"names":["A","B","C","D"]}"#,
    #"{"type":"start_kyoku","bakaze":"E","dora_marker":"9m","kyoku":1,"honba":0,"kyotaku":0,"oya":0,"scores":[25000,25000,25000,25000],"tehais":[["5mr","2m","3m","4m","6m","7m","5p","6p","8p","4s","5s","7s","E"],["?","?","?","?","?","?","?","?","?","?","?","?","?"],["?","?","?","?","?","?","?","?","?","?","?","?","?"],["?","?","?","?","?","?","?","?","?","?","?","?","?"]]}"#,

    // 手上唯一的五萬是紅五 → mask[4]=0、mask[34]=1
    #"{"type":"tsumo","actor":0,"pai":"9p"}"#,
    // 手切紅五（不是摸切——摸進來的是 9p）
    #"{"type":"dahai","actor":0,"pai":"5mr","tsumogiri":false}"#,

    #"{"type":"tsumo","actor":1,"pai":"?"}"#,
    #"{"type":"dahai","actor":1,"pai":"W","tsumogiri":true}"#,
    #"{"type":"tsumo","actor":2,"pai":"?"}"#,
    #"{"type":"dahai","actor":2,"pai":"N","tsumogiri":true}"#,
    #"{"type":"tsumo","actor":3,"pai":"?"}"#,
    #"{"type":"dahai","actor":3,"pai":"P","tsumogiri":true}"#,

    // 摸紅五筒，手上已有普通 5p → mask[13] 與 mask[35] 都要是 1
    #"{"type":"tsumo","actor":0,"pai":"5pr"}"#,
    #"{"type":"dahai","actor":0,"pai":"8p","tsumogiri":false}"#,
]

/// 紅五劇本 B：立直成立後摸紅五——唯一的合法動作就是摸切那張紅五
///
/// 立直後只能摸切，`discardCandidatesAka()` 只會打開 `tsumo.indexWithAka` 那一格。
/// 摸到紅五時那格就是 34，整個 mask 只有這一格是 1。
/// 這是實測到 bot 停手的原局面：decode(34) 回 nil → react 回 nil → 呼叫端當成
/// 「不需要動作」→ 等到 server 逾時。
private let akaRiichiEvents: [String] = [
    #"{"type":"start_game","id":0,"names":["A","B","C","D"]}"#,
    #"{"type":"start_kyoku","bakaze":"E","dora_marker":"9m","kyoku":1,"honba":0,"kyotaku":0,"oya":0,"scores":[25000,25000,25000,25000],"tehais":[["2m","3m","4m","6m","7m","8m","2p","3p","4p","5p","5p","7s","8s"],["?","?","?","?","?","?","?","?","?","?","?","?","?"],["?","?","?","?","?","?","?","?","?","?","?","?","?"],["?","?","?","?","?","?","?","?","?","?","?","?","?"]]}"#,

    // 打掉 E 就是聽 6s/9s
    #"{"type":"tsumo","actor":0,"pai":"E"}"#,
    #"{"type":"reach","actor":0}"#,
    #"{"type":"dahai","actor":0,"pai":"E","tsumogiri":true}"#,
    #"{"type":"reach_accepted","actor":0}"#,

    #"{"type":"tsumo","actor":1,"pai":"?"}"#,
    #"{"type":"dahai","actor":1,"pai":"1m","tsumogiri":true}"#,
    #"{"type":"tsumo","actor":2,"pai":"?"}"#,
    #"{"type":"dahai","actor":2,"pai":"1p","tsumogiri":true}"#,
    #"{"type":"tsumo","actor":3,"pai":"?"}"#,
    #"{"type":"dahai","actor":3,"pai":"1s","tsumogiri":true}"#,

    // 立直後摸紅五萬：合法動作只有 index 34
    #"{"type":"tsumo","actor":0,"pai":"5mr"}"#,
    #"{"type":"dahai","actor":0,"pai":"5mr","tsumogiri":true}"#,
]

/// 紅五劇本 C：紅五參與吃／碰的組合
///
/// 莊家是 seat 3（自己的上家），所以它打的牌自己可以吃。
/// - 3m + 5mr 吃 4m（中間張）
/// - 5sr + 5s 碰 5s
/// 驗的是「被吃／碰吃掉的那張是紅五」時，obs 的手牌／副露候選與 mask 仍與 libriichi 一致。
private let akaMeldEvents: [String] = [
    #"{"type":"start_game","id":0,"names":["A","B","C","D"]}"#,
    #"{"type":"start_kyoku","bakaze":"E","dora_marker":"9m","kyoku":4,"honba":0,"kyotaku":0,"oya":3,"scores":[25000,25000,25000,25000],"tehais":[["3m","5mr","5sr","5s","1p","2p","3p","6p","7p","8p","2s","E","E"],["?","?","?","?","?","?","?","?","?","?","?","?","?"],["?","?","?","?","?","?","?","?","?","?","?","?","?"],["?","?","?","?","?","?","?","?","?","?","?","?","?"]]}"#,

    // 上家打 4m → 可以用 3m + 紅五萬吃（只有「中間張」這一種組合）
    #"{"type":"tsumo","actor":3,"pai":"?"}"#,
    #"{"type":"dahai","actor":3,"pai":"4m","tsumogiri":false}"#,

    // 這裡選擇不吃，輪到自己摸牌
    #"{"type":"tsumo","actor":0,"pai":"9s"}"#,
    #"{"type":"dahai","actor":0,"pai":"9s","tsumogiri":true}"#,

    // 下家打 5s → 可以用 5sr + 5s 碰
    #"{"type":"tsumo","actor":1,"pai":"?"}"#,
    #"{"type":"dahai","actor":1,"pai":"5s","tsumogiri":false}"#,

    // 一樣不碰，讓局面走下去
    #"{"type":"tsumo","actor":2,"pai":"?"}"#,
    #"{"type":"dahai","actor":2,"pai":"E","tsumogiri":false}"#,
]

// MARK: - 振聽劇本
//
// 原本五個劇本**一次榮和機會都沒有**，所以 ch861（振聽）與 mask[43]（榮）兩邊
// 永遠都是 0——「對拍零落差」在振聽這一段等於什麼都沒驗到。
//
// 下面六個劇本把 libriichi 的三種振聽各走一遍。共用的聽牌手是
// `234m 678m 234p 5p5p 6s6s`（斷么、5p/6s 雙碰），榮得了、也碰得到，
// 所以「不能榮但還能碰」的時點也會產生 ACTION，ch861 才讀得到。

/// 振聽 A：見逃 → 同巡振聽 → 自家摸打後解除
///
/// 這是本組的主劇本，四個關鍵時點都會被比對到：
/// - seat1 打 5p：可榮，此時**還沒**振聽（ch861=0）
/// - seat2 打 6s：見逃成立，不能榮但能碰（ch861=1，mask 沒有 43）
/// - 自家摸牌：同巡振聽**還在**（libriichi 不在摸牌時解除）
/// - 自家打牌之後 seat1 再打 6s：解除，可以榮
private let furitenMissEvents: [String] = [
    #"{"type":"start_game","id":0,"names":["A","B","C","D"]}"#,
    #"{"type":"start_kyoku","bakaze":"E","dora_marker":"E","kyoku":2,"honba":0,"kyotaku":0,"oya":1,"scores":[25000,25000,25000,25000],"tehais":[["2m","3m","4m","6m","7m","8m","2p","3p","4p","5p","5p","6s","6s"],["?","?","?","?","?","?","?","?","?","?","?","?","?"],["?","?","?","?","?","?","?","?","?","?","?","?","?"],["?","?","?","?","?","?","?","?","?","?","?","?","?"]]}"#,
    #"{"type":"tsumo","actor":1,"pai":"?"}"#,
    #"{"type":"dahai","actor":1,"pai":"5p","tsumogiri":false}"#,
    #"{"type":"tsumo","actor":2,"pai":"?"}"#,
    #"{"type":"dahai","actor":2,"pai":"6s","tsumogiri":false}"#,
    #"{"type":"tsumo","actor":3,"pai":"?"}"#,
    #"{"type":"dahai","actor":3,"pai":"1m","tsumogiri":true}"#,
    #"{"type":"tsumo","actor":0,"pai":"9m"}"#,
    #"{"type":"dahai","actor":0,"pai":"9m","tsumogiri":true}"#,
    #"{"type":"tsumo","actor":1,"pai":"?"}"#,
    #"{"type":"dahai","actor":1,"pai":"6s","tsumogiri":false}"#,
    #"{"type":"tsumo","actor":2,"pai":"?"}"#,
    #"{"type":"dahai","actor":2,"pai":"5p","tsumogiri":false}"#,
]

/// 振聽 B：見逃緊接自家摸牌 —— 延後標記的時序
///
/// 上家打出待牌、自己見逃，**下一個事件就是自家摸牌**。
/// 見逃那一格必須是 0、緊接的摸牌那一格必須是 1，時序錯一格就會被抓到。
private let furitenMissThenTsumoEvents: [String] = [
    #"{"type":"start_game","id":0,"names":["A","B","C","D"]}"#,
    #"{"type":"start_kyoku","bakaze":"E","dora_marker":"E","kyoku":2,"honba":0,"kyotaku":0,"oya":1,"scores":[25000,25000,25000,25000],"tehais":[["2m","3m","4m","6m","7m","8m","2p","3p","4p","5p","5p","6s","6s"],["?","?","?","?","?","?","?","?","?","?","?","?","?"],["?","?","?","?","?","?","?","?","?","?","?","?","?"],["?","?","?","?","?","?","?","?","?","?","?","?","?"]]}"#,
    #"{"type":"tsumo","actor":1,"pai":"?"}"#,
    #"{"type":"dahai","actor":1,"pai":"9m","tsumogiri":true}"#,
    #"{"type":"tsumo","actor":2,"pai":"?"}"#,
    #"{"type":"dahai","actor":2,"pai":"9p","tsumogiri":true}"#,
    #"{"type":"tsumo","actor":3,"pai":"?"}"#,
    #"{"type":"dahai","actor":3,"pai":"5p","tsumogiri":false}"#,
    #"{"type":"tsumo","actor":0,"pai":"1m"}"#,
    #"{"type":"dahai","actor":0,"pai":"1m","tsumogiri":true}"#,
    #"{"type":"tsumo","actor":1,"pai":"?"}"#,
    #"{"type":"dahai","actor":1,"pai":"6s","tsumogiri":false}"#,
]

/// 振聽 C：立直後見逃 —— 永久振聽
///
/// 立直成立後聽牌不會再變，振聽只增不減：自家摸切**不會**把它洗掉。
/// 最後 seat1 再打 6s 時 libriichi 完全不回 ACTION（立直中除了榮沒別的可做），
/// 純 Swift 若誤判成可榮就會在「需要動作的判定不一致」被抓出來。
private let furitenRiichiEvents: [String] = [
    #"{"type":"start_game","id":0,"names":["A","B","C","D"]}"#,
    #"{"type":"start_kyoku","bakaze":"E","dora_marker":"E","kyoku":1,"honba":0,"kyotaku":0,"oya":0,"scores":[25000,25000,25000,25000],"tehais":[["2m","3m","4m","6m","7m","8m","2p","3p","4p","5p","5p","6s","6s"],["?","?","?","?","?","?","?","?","?","?","?","?","?"],["?","?","?","?","?","?","?","?","?","?","?","?","?"],["?","?","?","?","?","?","?","?","?","?","?","?","?"]]}"#,
    #"{"type":"tsumo","actor":0,"pai":"1m"}"#,
    #"{"type":"reach","actor":0}"#,
    #"{"type":"dahai","actor":0,"pai":"1m","tsumogiri":true}"#,
    #"{"type":"reach_accepted","actor":0}"#,
    #"{"type":"tsumo","actor":1,"pai":"?"}"#,
    #"{"type":"dahai","actor":1,"pai":"5p","tsumogiri":false}"#,
    #"{"type":"tsumo","actor":2,"pai":"?"}"#,
    #"{"type":"dahai","actor":2,"pai":"9m","tsumogiri":true}"#,
    #"{"type":"tsumo","actor":3,"pai":"?"}"#,
    #"{"type":"dahai","actor":3,"pai":"9p","tsumogiri":true}"#,
    #"{"type":"tsumo","actor":0,"pai":"9s"}"#,
    #"{"type":"dahai","actor":0,"pai":"9s","tsumogiri":true}"#,
    #"{"type":"tsumo","actor":1,"pai":"?"}"#,
    #"{"type":"dahai","actor":1,"pai":"6s","tsumogiri":false}"#,
]

/// 振聽 D：捨牌振聽會隨聽牌改變而解除
///
/// 一向聽時先打掉 8s，之後才聽上 5s/8s → 捨牌振聽；再改聽 5s 嵌張（5s 沒打過）→ 解除。
/// 捨牌振聽是**算出來的**，不是黏著的旗標——這一條就是在驗那件事。
///
/// 刻意繞開「自摸到自己的待牌」：那會讓 libriichi 走 SP 表的 fallback 分支
/// （用最小自摸點數當期望值，本劇本的莊家第一巡還會算成天和），
/// 而純 Swift 那兩格目前留 0。那是單人期望值表的缺口，與振聽無關，
/// 不該混進這條劇本的驗收裡。
private let furitenDiscardEvents: [String] = [
    #"{"type":"start_game","id":0,"names":["A","B","C","D"]}"#,
    #"{"type":"start_kyoku","bakaze":"E","dora_marker":"E","kyoku":1,"honba":0,"kyotaku":0,"oya":0,"scores":[25000,25000,25000,25000],"tehais":[["2m","3m","4m","6m","7m","8m","2p","3p","4p","5p","5p","8s","E"],["?","?","?","?","?","?","?","?","?","?","?","?","?"],["?","?","?","?","?","?","?","?","?","?","?","?","?"],["?","?","?","?","?","?","?","?","?","?","?","?","?"]]}"#,
    // 一向聽，先把 8s 打掉（此刻還沒聽牌，不構成振聽）
    #"{"type":"tsumo","actor":0,"pai":"6s"}"#,
    #"{"type":"dahai","actor":0,"pai":"8s","tsumogiri":false}"#,
    #"{"type":"tsumo","actor":1,"pai":"?"}"#,
    #"{"type":"dahai","actor":1,"pai":"9m","tsumogiri":true}"#,
    #"{"type":"tsumo","actor":2,"pai":"?"}"#,
    #"{"type":"dahai","actor":2,"pai":"9p","tsumogiri":true}"#,
    #"{"type":"tsumo","actor":3,"pai":"?"}"#,
    #"{"type":"dahai","actor":3,"pai":"N","tsumogiri":true}"#,
    // 摸 7s 打 E → 聽 5s/8s，8s 已經打過 → 捨牌振聽
    #"{"type":"tsumo","actor":0,"pai":"7s"}"#,
    #"{"type":"dahai","actor":0,"pai":"E","tsumogiri":false}"#,
    // seat1 打 5p：可以碰（手上 5p5p），所以讀得到 ch861＝1
    #"{"type":"tsumo","actor":1,"pai":"?"}"#,
    #"{"type":"dahai","actor":1,"pai":"5p","tsumogiri":false}"#,
    #"{"type":"tsumo","actor":2,"pai":"?"}"#,
    #"{"type":"dahai","actor":2,"pai":"N","tsumogiri":true}"#,
    #"{"type":"tsumo","actor":3,"pai":"?"}"#,
    #"{"type":"dahai","actor":3,"pai":"N","tsumogiri":true}"#,
    // 摸 4s 打 7s → 改聽 5s 嵌張，5s 沒打過 → 捨牌振聽解除
    #"{"type":"tsumo","actor":0,"pai":"4s"}"#,
    #"{"type":"dahai","actor":0,"pai":"7s","tsumogiri":false}"#,
    #"{"type":"tsumo","actor":1,"pai":"?"}"#,
    #"{"type":"dahai","actor":1,"pai":"5p","tsumogiri":false}"#,
]

/// 振聽 E：無役聽牌 —— 待牌流過去就**當下**進振聽
///
/// `234m 567p 234s 5p5p 9s9s` 聽 5p/8p/9s，榮和沒有任何役（不斷么、不平和、無役牌）。
/// libriichi 在這種局面：mask[43] 是 0（沒役不能榮），而且 ch861 在待牌流過去的**那一格**
/// 就變成 1（沒有「要不要榮」的選擇，不需要延後）。同時也驗了榮和的役判定——
/// 少了它純 Swift 會把無役聽牌當成可榮。
private let furitenNoYakuEvents: [String] = [
    #"{"type":"start_game","id":0,"names":["A","B","C","D"]}"#,
    #"{"type":"start_kyoku","bakaze":"E","dora_marker":"E","kyoku":2,"honba":0,"kyotaku":0,"oya":1,"scores":[25000,25000,25000,25000],"tehais":[["2m","3m","4m","5p","6p","7p","2s","3s","4s","5p","5p","9s","9s"],["?","?","?","?","?","?","?","?","?","?","?","?","?"],["?","?","?","?","?","?","?","?","?","?","?","?","?"],["?","?","?","?","?","?","?","?","?","?","?","?","?"]]}"#,
    #"{"type":"tsumo","actor":1,"pai":"?"}"#,
    #"{"type":"dahai","actor":1,"pai":"9s","tsumogiri":false}"#,
    #"{"type":"tsumo","actor":2,"pai":"?"}"#,
    #"{"type":"dahai","actor":2,"pai":"1m","tsumogiri":true}"#,
    #"{"type":"tsumo","actor":3,"pai":"?"}"#,
    #"{"type":"dahai","actor":3,"pai":"1p","tsumogiri":true}"#,
    #"{"type":"tsumo","actor":0,"pai":"1s"}"#,
    #"{"type":"dahai","actor":0,"pai":"1s","tsumogiri":true}"#,
    #"{"type":"tsumo","actor":1,"pai":"?"}"#,
    #"{"type":"dahai","actor":1,"pai":"5p","tsumogiri":false}"#,
]

/// 振聽 F：同巡振聽在「碰完再打」之後同樣解除
///
/// 解除的觸發點是**自家打牌**，不是自家摸牌，所以副露後的那一張打牌也算。
/// 打 7s 之後改聽 8s 單騎（7s 不是新的待牌，不會另外造成捨牌振聽），
/// seat1 打 8s 時應該可以榮（副露斷么）。
private let furitenMeldEvents: [String] = [
    #"{"type":"start_game","id":0,"names":["A","B","C","D"]}"#,
    #"{"type":"start_kyoku","bakaze":"E","dora_marker":"E","kyoku":2,"honba":0,"kyotaku":0,"oya":1,"scores":[25000,25000,25000,25000],"tehais":[["2m","3m","4m","6m","7m","8m","2p","3p","4p","5p","5p","7s","8s"],["?","?","?","?","?","?","?","?","?","?","?","?","?"],["?","?","?","?","?","?","?","?","?","?","?","?","?"],["?","?","?","?","?","?","?","?","?","?","?","?","?"]]}"#,
    #"{"type":"tsumo","actor":1,"pai":"?"}"#,
    #"{"type":"dahai","actor":1,"pai":"6s","tsumogiri":false}"#,
    #"{"type":"tsumo","actor":2,"pai":"?"}"#,
    #"{"type":"dahai","actor":2,"pai":"5p","tsumogiri":false}"#,
    #"{"type":"pon","actor":0,"target":2,"pai":"5p","consumed":["5p","5p"]}"#,
    #"{"type":"dahai","actor":0,"pai":"7s","tsumogiri":false}"#,
    #"{"type":"tsumo","actor":1,"pai":"?"}"#,
    #"{"type":"dahai","actor":1,"pai":"8s","tsumogiri":false}"#,
]

// MARK: - 食い替え（kuikae）劇本
//
// 原本所有劇本的吃／碰都是**別人**做的（唯一的自家碰在 furiten-meld，
// 而那個時點被 runBoth 當成已知缺口跳過），所以「自家副露之後要打哪一張」
// 從來沒有進過 oracle 比對——`forbiddenTiles` 恆 false 也不會被抓到。
//
// 下面七個劇本把食い替え的各種形狀走一遍（吃的三種位置＋兩種花色邊界＋碰＋碰紅五），
// 每一條都滿足兩個條件：
//   1. 被禁的那幾張**還留在手上**（否則 mask 那格本來就是 0，等於沒驗）
//   2. 副露打牌之後會再走到一次自家摸牌（驗禁手有解除，不是永久黏住）
//
// 座位安排：自己是 seat 0，莊家 seat 1，所以上家是 seat 3——吃只能吃上家。

/// 食い替え A：吃上家打的 3m（吃的牌在順子最小位）
///
/// 手上 3m4m5m6m，用 4m5m 吃 3m 成 345m。
/// 禁手：3m（現物）與 6m（筋）——兩張都還在手上，mask[2] 與 mask[5] 必須是 0。
private let kuikaeChiLowEvents: [String] = [
    #"{"type":"start_game","id":0,"names":["A","B","C","D"]}"#,
    #"{"type":"start_kyoku","bakaze":"E","dora_marker":"E","kyoku":2,"honba":0,"kyotaku":0,"oya":1,"scores":[25000,25000,25000,25000],"tehais":[["3m","4m","5m","6m","1p","2p","3p","5p","6p","7p","2s","3s","4s"],["?","?","?","?","?","?","?","?","?","?","?","?","?"],["?","?","?","?","?","?","?","?","?","?","?","?","?"],["?","?","?","?","?","?","?","?","?","?","?","?","?"]]}"#,
    #"{"type":"tsumo","actor":1,"pai":"?"}"#,
    #"{"type":"dahai","actor":1,"pai":"S","tsumogiri":true}"#,
    #"{"type":"tsumo","actor":2,"pai":"?"}"#,
    #"{"type":"dahai","actor":2,"pai":"W","tsumogiri":true}"#,
    #"{"type":"tsumo","actor":3,"pai":"?"}"#,
    #"{"type":"dahai","actor":3,"pai":"3m","tsumogiri":false}"#,
    #"{"type":"chi","actor":0,"target":3,"pai":"3m","consumed":["4m","5m"]}"#,
    #"{"type":"dahai","actor":0,"pai":"1p","tsumogiri":false}"#,
    // 走到下一次自家摸牌，驗禁手已解除
    #"{"type":"tsumo","actor":1,"pai":"?"}"#,
    #"{"type":"dahai","actor":1,"pai":"N","tsumogiri":true}"#,
    #"{"type":"tsumo","actor":2,"pai":"?"}"#,
    #"{"type":"dahai","actor":2,"pai":"P","tsumogiri":true}"#,
    #"{"type":"tsumo","actor":3,"pai":"?"}"#,
    #"{"type":"dahai","actor":3,"pai":"F","tsumogiri":true}"#,
    #"{"type":"tsumo","actor":0,"pai":"9s"}"#,
    #"{"type":"dahai","actor":0,"pai":"9s","tsumogiri":true}"#,
]

/// 食い替え B：吃上家打的 6m（吃的牌在順子最大位）
///
/// 手上 3m4m5m6m，用 4m5m 吃 6m 成 456m。
/// 禁手：6m（現物）與 3m（筋）。與 A 是鏡像，但走的是 `canChiHigh` 那一格。
private let kuikaeChiHighEvents: [String] = [
    #"{"type":"start_game","id":0,"names":["A","B","C","D"]}"#,
    #"{"type":"start_kyoku","bakaze":"E","dora_marker":"E","kyoku":2,"honba":0,"kyotaku":0,"oya":1,"scores":[25000,25000,25000,25000],"tehais":[["3m","4m","5m","6m","1p","2p","3p","5p","6p","7p","2s","3s","4s"],["?","?","?","?","?","?","?","?","?","?","?","?","?"],["?","?","?","?","?","?","?","?","?","?","?","?","?"],["?","?","?","?","?","?","?","?","?","?","?","?","?"]]}"#,
    #"{"type":"tsumo","actor":1,"pai":"?"}"#,
    #"{"type":"dahai","actor":1,"pai":"S","tsumogiri":true}"#,
    #"{"type":"tsumo","actor":2,"pai":"?"}"#,
    #"{"type":"dahai","actor":2,"pai":"W","tsumogiri":true}"#,
    #"{"type":"tsumo","actor":3,"pai":"?"}"#,
    #"{"type":"dahai","actor":3,"pai":"6m","tsumogiri":false}"#,
    #"{"type":"chi","actor":0,"target":3,"pai":"6m","consumed":["4m","5m"]}"#,
    #"{"type":"dahai","actor":0,"pai":"1p","tsumogiri":false}"#,
    #"{"type":"tsumo","actor":1,"pai":"?"}"#,
    #"{"type":"dahai","actor":1,"pai":"N","tsumogiri":true}"#,
    #"{"type":"tsumo","actor":2,"pai":"?"}"#,
    #"{"type":"dahai","actor":2,"pai":"P","tsumogiri":true}"#,
    #"{"type":"tsumo","actor":3,"pai":"?"}"#,
    #"{"type":"dahai","actor":3,"pai":"F","tsumogiri":true}"#,
    #"{"type":"tsumo","actor":0,"pai":"9s"}"#,
    #"{"type":"dahai","actor":0,"pai":"9s","tsumogiri":true}"#,
]

/// 食い替え C：嵌張吃（吃的牌在順子中間）—— **只有現物**，沒有筋
///
/// 手上 3m4m4m5m，用 3m5m 吃 4m 成 345m，手上還留一對 4m。
/// 禁手只有 4m。這一條的作用是防止「筋的規則被套用到嵌張」——
/// 那會多禁掉 1m/7m，是實作食い替え時最容易寫錯的地方。
private let kuikaeChiMidEvents: [String] = [
    #"{"type":"start_game","id":0,"names":["A","B","C","D"]}"#,
    #"{"type":"start_kyoku","bakaze":"E","dora_marker":"E","kyoku":2,"honba":0,"kyotaku":0,"oya":1,"scores":[25000,25000,25000,25000],"tehais":[["3m","4m","4m","5m","1p","2p","3p","5p","6p","8p","2s","3s","4s"],["?","?","?","?","?","?","?","?","?","?","?","?","?"],["?","?","?","?","?","?","?","?","?","?","?","?","?"],["?","?","?","?","?","?","?","?","?","?","?","?","?"]]}"#,
    #"{"type":"tsumo","actor":1,"pai":"?"}"#,
    #"{"type":"dahai","actor":1,"pai":"S","tsumogiri":true}"#,
    #"{"type":"tsumo","actor":2,"pai":"?"}"#,
    #"{"type":"dahai","actor":2,"pai":"W","tsumogiri":true}"#,
    #"{"type":"tsumo","actor":3,"pai":"?"}"#,
    #"{"type":"dahai","actor":3,"pai":"4m","tsumogiri":false}"#,
    #"{"type":"chi","actor":0,"target":3,"pai":"4m","consumed":["3m","5m"]}"#,
    #"{"type":"dahai","actor":0,"pai":"8p","tsumogiri":false}"#,
    #"{"type":"tsumo","actor":1,"pai":"?"}"#,
    #"{"type":"dahai","actor":1,"pai":"N","tsumogiri":true}"#,
    #"{"type":"tsumo","actor":2,"pai":"?"}"#,
    #"{"type":"dahai","actor":2,"pai":"P","tsumogiri":true}"#,
    #"{"type":"tsumo","actor":3,"pai":"?"}"#,
    #"{"type":"dahai","actor":3,"pai":"F","tsumogiri":true}"#,
    #"{"type":"tsumo","actor":0,"pai":"9s"}"#,
    #"{"type":"dahai","actor":0,"pai":"9s","tsumogiri":true}"#,
]

/// 食い替え C2：吃 7m 成 789m —— 筋那張（「10m」）不存在，不能滾到下一個花色
///
/// `targetIdx + 3` = 9，那是 1p。手上刻意留著 1p：若實作沒擋花色邊界，
/// mask[9] 會被關掉，對拍立刻抓到。
private let kuikaeChiEdgeHighEvents: [String] = [
    #"{"type":"start_game","id":0,"names":["A","B","C","D"]}"#,
    #"{"type":"start_kyoku","bakaze":"E","dora_marker":"E","kyoku":2,"honba":0,"kyotaku":0,"oya":1,"scores":[25000,25000,25000,25000],"tehais":[["7m","8m","9m","1p","2p","3p","5p","6p","7p","2s","3s","4s","E"],["?","?","?","?","?","?","?","?","?","?","?","?","?"],["?","?","?","?","?","?","?","?","?","?","?","?","?"],["?","?","?","?","?","?","?","?","?","?","?","?","?"]]}"#,
    #"{"type":"tsumo","actor":1,"pai":"?"}"#,
    #"{"type":"dahai","actor":1,"pai":"S","tsumogiri":true}"#,
    #"{"type":"tsumo","actor":2,"pai":"?"}"#,
    #"{"type":"dahai","actor":2,"pai":"W","tsumogiri":true}"#,
    #"{"type":"tsumo","actor":3,"pai":"?"}"#,
    #"{"type":"dahai","actor":3,"pai":"7m","tsumogiri":false}"#,
    #"{"type":"chi","actor":0,"target":3,"pai":"7m","consumed":["8m","9m"]}"#,
    #"{"type":"dahai","actor":0,"pai":"E","tsumogiri":false}"#,
    #"{"type":"tsumo","actor":1,"pai":"?"}"#,
    #"{"type":"dahai","actor":1,"pai":"N","tsumogiri":true}"#,
    #"{"type":"tsumo","actor":2,"pai":"?"}"#,
    #"{"type":"dahai","actor":2,"pai":"P","tsumogiri":true}"#,
    #"{"type":"tsumo","actor":3,"pai":"?"}"#,
    #"{"type":"dahai","actor":3,"pai":"F","tsumogiri":true}"#,
    #"{"type":"tsumo","actor":0,"pai":"9s"}"#,
    #"{"type":"dahai","actor":0,"pai":"9s","tsumogiri":true}"#,
]

/// 食い替え C3：吃 3m 成 123m —— 筋那張是負索引，同樣不存在
///
/// `targetIdx - 3` = -1。少了下界檢查在 Swift 是直接 crash，不是靜默錯誤，
/// 所以這條劇本同時當成邊界的煙霧測試。
private let kuikaeChiEdgeLowEvents: [String] = [
    #"{"type":"start_game","id":0,"names":["A","B","C","D"]}"#,
    #"{"type":"start_kyoku","bakaze":"E","dora_marker":"E","kyoku":2,"honba":0,"kyotaku":0,"oya":1,"scores":[25000,25000,25000,25000],"tehais":[["1m","2m","3m","5p","6p","7p","2s","3s","4s","7s","8s","9s","E"],["?","?","?","?","?","?","?","?","?","?","?","?","?"],["?","?","?","?","?","?","?","?","?","?","?","?","?"],["?","?","?","?","?","?","?","?","?","?","?","?","?"]]}"#,
    #"{"type":"tsumo","actor":1,"pai":"?"}"#,
    #"{"type":"dahai","actor":1,"pai":"S","tsumogiri":true}"#,
    #"{"type":"tsumo","actor":2,"pai":"?"}"#,
    #"{"type":"dahai","actor":2,"pai":"W","tsumogiri":true}"#,
    #"{"type":"tsumo","actor":3,"pai":"?"}"#,
    #"{"type":"dahai","actor":3,"pai":"3m","tsumogiri":false}"#,
    #"{"type":"chi","actor":0,"target":3,"pai":"3m","consumed":["1m","2m"]}"#,
    #"{"type":"dahai","actor":0,"pai":"E","tsumogiri":false}"#,
    #"{"type":"tsumo","actor":1,"pai":"?"}"#,
    #"{"type":"dahai","actor":1,"pai":"N","tsumogiri":true}"#,
    #"{"type":"tsumo","actor":2,"pai":"?"}"#,
    #"{"type":"dahai","actor":2,"pai":"P","tsumogiri":true}"#,
    #"{"type":"tsumo","actor":3,"pai":"?"}"#,
    #"{"type":"dahai","actor":3,"pai":"F","tsumogiri":true}"#,
    #"{"type":"tsumo","actor":0,"pai":"9p"}"#,
    #"{"type":"dahai","actor":0,"pai":"9p","tsumogiri":true}"#,
]

/// 食い替え D：碰 —— 只禁現物，沒有筋
///
/// 手上 5p5p5p，碰下家打的 5p，手上還留一張 5p → mask[13] 必須是 0。
/// 碰完手上還有 5p，所以下一次摸牌時 `canKakan` 也會亮，順便走到加槓那一格。
private let kuikaePonEvents: [String] = [
    #"{"type":"start_game","id":0,"names":["A","B","C","D"]}"#,
    #"{"type":"start_kyoku","bakaze":"E","dora_marker":"1s","kyoku":2,"honba":0,"kyotaku":0,"oya":1,"scores":[25000,25000,25000,25000],"tehais":[["5p","5p","5p","1m","2m","3m","7m","8m","9m","2s","3s","4s","E"],["?","?","?","?","?","?","?","?","?","?","?","?","?"],["?","?","?","?","?","?","?","?","?","?","?","?","?"],["?","?","?","?","?","?","?","?","?","?","?","?","?"]]}"#,
    #"{"type":"tsumo","actor":1,"pai":"?"}"#,
    #"{"type":"dahai","actor":1,"pai":"5p","tsumogiri":false}"#,
    #"{"type":"pon","actor":0,"target":1,"pai":"5p","consumed":["5p","5p"]}"#,
    #"{"type":"dahai","actor":0,"pai":"E","tsumogiri":false}"#,
    #"{"type":"tsumo","actor":2,"pai":"?"}"#,
    #"{"type":"dahai","actor":2,"pai":"W","tsumogiri":true}"#,
    #"{"type":"tsumo","actor":3,"pai":"?"}"#,
    #"{"type":"dahai","actor":3,"pai":"N","tsumogiri":true}"#,
    #"{"type":"tsumo","actor":0,"pai":"9p"}"#,
    #"{"type":"dahai","actor":0,"pai":"9p","tsumogiri":true}"#,
]

/// 食い替え E：碰完手上只剩紅五 —— 禁手要同時關掉普通五與紅五兩格
///
/// 手上 5s5s5sr，用兩張普通 5s 碰，手上只剩 5sr。
/// 禁手是「5s 這個牌種」，所以 mask[22]（普通五索）與 mask[36]（紅五索）都要是 0；
/// 只擋 34 格那一版會讓紅五那格漏出來，送出去一樣是犯規打牌。
/// 解除之後 mask[36] 會變 1、mask[22] 仍是 0（手上那張五索是紅的，見 `applyAkaToCandidates`）。
private let kuikaePonAkaEvents: [String] = [
    #"{"type":"start_game","id":0,"names":["A","B","C","D"]}"#,
    #"{"type":"start_kyoku","bakaze":"E","dora_marker":"9m","kyoku":2,"honba":0,"kyotaku":0,"oya":1,"scores":[25000,25000,25000,25000],"tehais":[["5s","5s","5sr","1m","2m","3m","7m","8m","9m","2s","3s","4s","E"],["?","?","?","?","?","?","?","?","?","?","?","?","?"],["?","?","?","?","?","?","?","?","?","?","?","?","?"],["?","?","?","?","?","?","?","?","?","?","?","?","?"]]}"#,
    #"{"type":"tsumo","actor":1,"pai":"?"}"#,
    #"{"type":"dahai","actor":1,"pai":"5s","tsumogiri":false}"#,
    #"{"type":"pon","actor":0,"target":1,"pai":"5s","consumed":["5s","5s"]}"#,
    #"{"type":"dahai","actor":0,"pai":"E","tsumogiri":false}"#,
    #"{"type":"tsumo","actor":2,"pai":"?"}"#,
    #"{"type":"dahai","actor":2,"pai":"W","tsumogiri":true}"#,
    #"{"type":"tsumo","actor":3,"pai":"?"}"#,
    #"{"type":"dahai","actor":3,"pai":"N","tsumogiri":true}"#,
    #"{"type":"tsumo","actor":0,"pai":"9p"}"#,
    #"{"type":"dahai","actor":0,"pai":"9p","tsumogiri":true}"#,
]

/// 待牌枯竭：四張全部現身的牌不算「聽」
///
/// 這條劇本是補食い替え劇本時被 oracle 抓出來的鄰近缺口，跟副露無關：
/// `234m 678m 567p 345s` 單騎 9p，三家各打掉一張 9p 之後，
/// 加上自己手上那張，9p 已經四張全現——**摸不到也榮不到**，libriichi 因此
/// 把它從 waits 拿掉（ch860 那一格清空）。
///
/// 特意不用副露來湊滿四張：那樣「自家持有 4 張」與「場上已見 4 張」兩種判準
/// 會給出同樣的答案，分不出 libriichi 用的是哪一個。這裡三張在別人的河裡，
/// 只有「已見四張」這個判準會排除它。
///
/// 手是無役聽牌（9p 單騎，不斷么、不平和），所以別人打 9p 時不會被問要不要榮，
/// 劇本才走得下去。
private let waitsDeadTileEvents: [String] = [
    #"{"type":"start_game","id":0,"names":["A","B","C","D"]}"#,
    #"{"type":"start_kyoku","bakaze":"E","dora_marker":"E","kyoku":1,"honba":0,"kyotaku":0,"oya":0,"scores":[25000,25000,25000,25000],"tehais":[["2m","3m","4m","6m","7m","8m","5p","6p","7p","9p","3s","4s","5s"],["?","?","?","?","?","?","?","?","?","?","?","?","?"],["?","?","?","?","?","?","?","?","?","?","?","?","?"],["?","?","?","?","?","?","?","?","?","?","?","?","?"]]}"#,
    #"{"type":"tsumo","actor":0,"pai":"1s"}"#,
    #"{"type":"dahai","actor":0,"pai":"1s","tsumogiri":true}"#,
    // 三家各打一張 9p：加上自己手上那張，四張全現
    #"{"type":"tsumo","actor":1,"pai":"?"}"#,
    #"{"type":"dahai","actor":1,"pai":"9p","tsumogiri":true}"#,
    #"{"type":"tsumo","actor":2,"pai":"?"}"#,
    #"{"type":"dahai","actor":2,"pai":"9p","tsumogiri":true}"#,
    #"{"type":"tsumo","actor":3,"pai":"?"}"#,
    #"{"type":"dahai","actor":3,"pai":"9p","tsumogiri":true}"#,
    // 自家摸打一次，waits 在這裡重算
    #"{"type":"tsumo","actor":0,"pai":"1m"}"#,
    #"{"type":"dahai","actor":0,"pai":"1m","tsumogiri":true}"#,
    #"{"type":"tsumo","actor":1,"pai":"?"}"#,
    #"{"type":"dahai","actor":1,"pai":"E","tsumogiri":true}"#,
    #"{"type":"tsumo","actor":2,"pai":"?"}"#,
    #"{"type":"dahai","actor":2,"pai":"E","tsumogiri":true}"#,
    #"{"type":"tsumo","actor":3,"pai":"?"}"#,
    #"{"type":"dahai","actor":3,"pai":"E","tsumogiri":true}"#,
    #"{"type":"tsumo","actor":0,"pai":"1m"}"#,
    #"{"type":"dahai","actor":0,"pai":"1m","tsumogiri":true}"#,
]

/// 對拍劇本清單
private let parityScenarios: [(label: String, events: [String])] = [
    ("minimal", minimalEvents),
    ("full", fullEvents),
    ("aka-discard", akaDiscardEvents),
    ("aka-riichi", akaRiichiEvents),
    ("aka-meld", akaMeldEvents),
    ("furiten-miss", furitenMissEvents),
    ("furiten-miss-then-tsumo", furitenMissThenTsumoEvents),
    ("furiten-riichi", furitenRiichiEvents),
    ("furiten-discard", furitenDiscardEvents),
    ("furiten-no-yaku", furitenNoYakuEvents),
    ("furiten-meld", furitenMeldEvents),
    ("kuikae-chi-low", kuikaeChiLowEvents),
    ("kuikae-chi-high", kuikaeChiHighEvents),
    ("kuikae-chi-mid", kuikaeChiMidEvents),
    ("kuikae-chi-edge-high", kuikaeChiEdgeHighEvents),
    ("kuikae-chi-edge-low", kuikaeChiEdgeLowEvents),
    ("kuikae-pon", kuikaePonEvents),
    ("kuikae-pon-aka", kuikaePonAkaEvents),
    ("waits-dead-tile", waitsDeadTileEvents),
]

/// 食い替え劇本的預期
///
/// - `forbidden`：副露後打牌那一格該關掉的 mask 索引（0-33 普通牌、34-36 紅五）
/// - `stillAllowed`：同一格必須**維持開著**的索引。用來釘住「不該多禁」的那幾張——
///   `forbidden` 只證明有禁到，證明不了沒有禁過頭。
/// - `releasedAfterDraw`：下一次自家摸牌時該放行的索引。不一定等於 `forbidden`：
///   手上只剩紅五時，解除後亮的是紅五那格而不是普通五那格。
private let kuikaeExpectations: [(
    label: String, forbidden: [Int], stillAllowed: [Int], releasedAfterDraw: [Int]
)] = [
    // 3m 現物 + 6m 筋
    ("kuikae-chi-low", [2, 5], [9, 19], [2, 5]),
    // 6m 現物 + 3m 筋
    ("kuikae-chi-high", [5, 2], [9, 19], [5, 2]),
    // 4m 現物；嵌張沒有筋 → 1m(0) 與 7m(6) 都不該被牽連
    ("kuikae-chi-mid", [3], [9, 19], [3]),
    // 7m 現物；筋落在「10m」→ 不存在，1p(9) 必須維持可打
    ("kuikae-chi-edge-high", [6], [9, 19], [6]),
    // 3m 現物；筋是負索引 → 不存在，2s(19) 與 7s(24) 必須維持可打
    ("kuikae-chi-edge-low", [2], [19, 24], [2]),
    // 5p 現物；碰沒有筋 → 2p(10) 與 8p(16) 不該被牽連（手上沒有，改釘 1m/2s）
    ("kuikae-pon", [13], [0, 19], [13]),
    // 5s 牌種（普通五與紅五兩格一起關）
    ("kuikae-pon-aka", [22, 36], [0, 19], [36]),
]

/// 振聽劇本的標籤
private let furitenScenarioLabels = [
    "furiten-miss", "furiten-miss-then-tsumo", "furiten-riichi",
    "furiten-discard", "furiten-no-yaku", "furiten-meld",
]

/// observation 裡的振聽那一格（`ObsEncoder` 佈局，見 libriichi `obs_repr.rs`）
private let furitenChannel = 861

/// 一次比對結果
private struct ParitySnapshot {
    let label: String
    let oracle: (obs: [Float], mask: [Bool])
    let swift: (obs: [Float], mask: [Bool])
}

/// 是不是「自家宣告」事件（立直／吃／碰／槓），亦即宣告完還要再打一張的那種
private func isSelfDeclaration(_ json: String) -> Bool {
    guard json.contains(#""actor":0"#) else { return false }
    for type in ["reach", "chi", "pon", "daiminkan", "ankan", "kakan"]
    where json.contains("\"type\":\"\(type)\"") {
        return true
    }
    return false
}

/// 是不是「自家吃／碰」——副露完直接接一張打牌，而且那張打牌受食い替え限制
private func isSelfChiPon(_ json: String) -> Bool {
    guard json.contains(#""actor":0"#) else { return false }
    return json.contains(#""type":"chi""#) || json.contains(#""type":"pon""#)
}

/// 把同一串事件同時餵給 libriichi 與純 Swift，收集**每一個**需要動作的時點
private func runBoth(_ events: [String], label: String) -> [ParitySnapshot] {
    guard let oracle = LibRiichiOracle(playerId: 0) else { return [] }
    let state = PlayerState(playerId: 0)

    var snapshots: [ParitySnapshot] = []
    var pendingOracle: (obs: [Float], mask: [Bool])?

    for (i, json) in events.enumerated() {
        let oracleResult = oracle.update(json)
        if let oracleResult { pendingOracle = oracleResult }

        var swiftResult: (obs: [Float], mask: [Bool])?
        if let data = json.data(using: .utf8),
           let event = try? JSONDecoder().decode(MJAIEvent.self, from: data),
           state.update(event: event) {
            let encoded = ObsEncoder.encode(state: state)
            swiftResult = (encoded.0, encoded.1.map { $0 != 0 })
        }

        // 兩邊都認為需要動作時才比對；只有一邊需要動作本身就是落差，另外驗
        if let o = oracleResult, let s = swiftResult {
            snapshots.append(ParitySnapshot(label: "\(label)#\(i)", oracle: o, swift: s))
            pendingOracle = nil
        } else if let o = oracleResult, swiftResult == nil, isSelfChiPon(json), state.lastCans.canDiscard {
            // 自家吃／碰之後 MJAI 不會再送事件要你打牌：libriichi 回 ACTION_REQUIRED，
            // 純 Swift 的 `update` 回 false，那一張打牌是呼叫端用 `inferCurrentState()`
            // 驅動的——而它做的事就是「直接對當前狀態編碼」。
            //
            // 所以這裡照樣編一次來比對。**食い替え禁手正好只出現在這個時點**，
            // 不比對等於 oracle 永遠抓不到（`forbiddenTiles` 全 false 也會綠燈）。
            let encoded = ObsEncoder.encode(state: state)
            snapshots.append(ParitySnapshot(
                label: "\(label)#\(i)[副露後打牌]",
                oracle: o,
                swift: (encoded.0, encoded.1.map { $0 != 0 })))
            pendingOracle = nil
        } else if oracleResult != nil && swiftResult == nil && isSelfDeclaration(json) {
            // 剩下的已知缺口（見 tasks/mortalswift/README.md「對拍劇本已知缺口」）：
            // 自家宣告立直／槓之後 libriichi 同樣回 ACTION_REQUIRED，
            // 但純 Swift 的 `update` 回 false，且 `lastCans` 也沒有進入可打牌狀態。
            //
            // 紅五劇本必須走過「自家立直」才到得了「立直後摸紅五」，
            // 所以這裡明確跳過、不當成落差。真的要修那個缺口時把這個分支拔掉，
            // 對拍會立刻把它抓回來。
            continue
        } else if oracleResult != nil || swiftResult != nil {
            snapshots.append(ParitySnapshot(
                label: "\(label)#\(i)[需要動作的判定不一致 oracle=\(oracleResult != nil) swift=\(swiftResult != nil)]",
                oracle: oracleResult ?? (obs: [], mask: []),
                swift: swiftResult ?? (obs: [], mask: [])))
        }
    }
    _ = pendingOracle
    if !oracle.rejected.isEmpty {
        Issue.record("[\(label)] libriichi 拒收了 \(oracle.rejected.count) 個事件，對拍結果無效：\(oracle.rejected.first ?? "")")
        return []
    }
    return snapshots
}

/// 回傳不一致的 channel 索引
private func mismatchedChannels(_ snapshot: ParitySnapshot) -> [Int] {
    let width = 34
    guard snapshot.oracle.obs.count == snapshot.swift.obs.count else { return Array(0..<1012) }

    var result: [Int] = []
    for ch in 0..<ObsEncoder.obsChannels {
        for i in 0..<width where snapshot.oracle.obs[ch * width + i] != snapshot.swift.obs[ch * width + i] {
            result.append(ch)
            break
        }
    }
    return result
}

/// 已知尚未移植的區段（單人期望值表與役種判定），暫時排除在驗收之外。
///
/// 這不是「容許誤差」——是**明確標示還沒做完的部分**。移植完成後這個集合要清空。
private let knownUnportedChannels: Set<Int> = {
    let s: Set<Int> = []
    return s
}()

// MARK: - 測試

@Test func obsParityAgainstLibRiichi() throws {
    var allMismatched: Set<Int> = []
    var unportedHit: Set<Int> = []

    for (label, events) in parityScenarios {
        let snapshots = runBoth(events, label: label)
        #expect(!snapshots.isEmpty, "\(label) 劇本沒有產生任何需要動作的時點")

        for snapshot in snapshots {
            let mismatched = mismatchedChannels(snapshot)
            let unexpected = mismatched.filter { !knownUnportedChannels.contains($0) }
            unportedHit.formUnion(mismatched.filter { knownUnportedChannels.contains($0) })
            if !unexpected.isEmpty {
                print("[\(snapshot.label)] 未預期的落差 \(unexpected.count) 個: \(unexpected.prefix(40))")
            }
            allMismatched.formUnion(unexpected)
        }
    }

    print("=== obs 對拍結果 ===")
    print("已移植區段的落差: \(allMismatched.count) 個 channel")
    print("尚未移植區段的落差: \(unportedHit.count) 個 channel（單人期望值表 / 役種判定）")

    #expect(allMismatched.isEmpty,
            "已移植區段仍有 \(allMismatched.count) 個 channel 與 libriichi 不一致: \(allMismatched.sorted().prefix(40))")
}

@Test func maskParityAgainstLibRiichi() throws {
    for (label, events) in parityScenarios {
        let snapshots = runBoth(events, label: label)
        #expect(!snapshots.isEmpty, "\(label) 劇本沒有產生任何需要動作的時點")

        for snapshot in snapshots {
            guard snapshot.oracle.mask.count == snapshot.swift.mask.count else {
                Issue.record("[\(snapshot.label)] mask 長度不一致")
                continue
            }
            let diff = (0..<snapshot.oracle.mask.count).filter {
                snapshot.oracle.mask[$0] != snapshot.swift.mask[$0]
            }
            if !diff.isEmpty {
                print("[\(snapshot.label)] mask 落差 \(diff)")
                print("  libriichi: \(snapshot.oracle.mask.map { $0 ? 1 : 0 })")
                print("  swift    : \(snapshot.swift.mask.map { $0 ? 1 : 0 })")
            }
            #expect(diff.isEmpty, "[\(snapshot.label)] mask 有 \(diff.count) 格不一致")
        }
    }
}

/// 診斷用：印出仍不一致的 channel 明細
@Test func dumpMismatchedChannels() {
    let width = 34
    for (label, events) in parityScenarios {
        for snapshot in runBoth(events, label: label) {
            let mismatched = mismatchedChannels(snapshot).filter { !knownUnportedChannels.contains($0) }
            guard !mismatched.isEmpty else { continue }
            print("=== [\(snapshot.label)] 落差明細 ===")
            for ch in mismatched.prefix(20) {
                let o = Array(snapshot.oracle.obs[ch*width..<(ch+1)*width])
                let s = Array(snapshot.swift.obs[ch*width..<(ch+1)*width])
                let oNZ = o.enumerated().filter { $0.element != 0 }.map { "\($0.offset)=\($0.element)" }
                let sNZ = s.enumerated().filter { $0.element != 0 }.map { "\($0.offset)=\($0.element)" }
                print("ch\(ch): libriichi[\(oNZ.prefix(8).joined(separator: " "))] swift[\(sNZ.prefix(8).joined(separator: " "))]")
            }
        }
    }
}

/// 紅五劇本真的走到 mask 34-36 了嗎
///
/// 沒有這一條，前面兩個對拍測試可能只是「兩邊的紅五格都是 0」——
/// 那等於沒驗到任何東西。這裡直接斷言 libriichi 自己在這些時點打開了 34-36。
@Test func akaScenariosActuallyExerciseAkaMask() {
    var akaMaskSeen: Set<Int> = []
    var sawAkaOnlyDiscard = false

    for label in ["aka-discard", "aka-riichi", "aka-meld"] {
        guard let scenario = parityScenarios.first(where: { $0.label == label }) else {
            Issue.record("找不到劇本 \(label)")
            continue
        }
        for snapshot in runBoth(scenario.events, label: label) {
            for idx in 34...36 where snapshot.oracle.mask[idx] {
                akaMaskSeen.insert(idx)
            }
            // 「普通五那格關掉、只剩紅五那格」——decode 少了 34-36 分支時會停手的形狀
            if snapshot.oracle.mask[34] && !snapshot.oracle.mask[4] {
                sawAkaOnlyDiscard = true
            }
        }
    }

    #expect(akaMaskSeen.contains(34), "劇本沒有走到 mask[34]（紅五萬）")
    #expect(akaMaskSeen.contains(35), "劇本沒有走到 mask[35]（紅五筒）")
    #expect(akaMaskSeen.contains(36), "劇本沒有走到 mask[36]（紅五索）")
    #expect(sawAkaOnlyDiscard, "劇本沒有走到「唯一合法打牌是紅五」的局面")
}

/// 振聽劇本真的把 ch861 推到 1 又推回 0 了嗎
///
/// 沒有這一條，前面兩個對拍測試在振聽這一段可能只是「兩邊都是 0」。
/// 這裡直接對 **libriichi 自己的輸出**斷言：
/// - ch861 在這些劇本裡出現過 1（有進振聽）也出現過 0（有解除）
/// - mask[43]（榮）出現過 1（真的走到過榮和機會）也在 ch861=1 時是 0（振聽真的擋住榮）
///
/// 另外驗 ch861 確實是純 Swift 這邊 `atFuriten` 唯一影響的那一格，
/// 免得日後改佈局時這組斷言悄悄改成在驗別的東西。
@Test func furitenScenariosActuallyExerciseFuritenChannel() {
    var sawFuritenOn = false
    var sawFuritenOff = false
    var sawRonOffered = false
    var sawRonBlockedByFuriten = false

    for label in furitenScenarioLabels {
        guard let scenario = parityScenarios.first(where: { $0.label == label }) else {
            Issue.record("找不到劇本 \(label)")
            continue
        }
        let snapshots = runBoth(scenario.events, label: label)
        #expect(!snapshots.isEmpty, "\(label) 劇本沒有產生任何需要動作的時點")

        var furitenOnInThisScenario = false
        for snapshot in snapshots {
            guard snapshot.oracle.obs.count == ObsEncoder.obsChannels * 34 else { continue }
            let furiten = snapshot.oracle.obs[furitenChannel * 34] != 0
            if furiten { sawFuritenOn = true; furitenOnInThisScenario = true } else { sawFuritenOff = true }
            if snapshot.oracle.mask[PlayerState.ActionIndex.hora] {
                sawRonOffered = true
                #expect(!furiten, "[\(snapshot.label)] libriichi 在振聽狀態下仍給了榮和？")
            } else if furiten && snapshot.oracle.mask[PlayerState.ActionIndex.pass] {
                // 振聽中、還有別的可做（碰）但沒有榮 —— 正是振聽擋住榮的形狀
                sawRonBlockedByFuriten = true
            }
        }
        // 每一條劇本都必須真的走進振聽，否則改劇本時很容易悄悄退化成「兩邊都是 0」
        #expect(furitenOnInThisScenario, "劇本 \(label) 從頭到尾沒有走進振聽（ch861 一直是 0）")
    }

    #expect(sawFuritenOn, "劇本沒有走到「振聽中」（ch861=1）")
    #expect(sawFuritenOff, "劇本沒有走到「非振聽」（ch861=0）")
    #expect(sawRonOffered, "劇本沒有走到任何榮和機會（mask[43]=1）")
    #expect(sawRonBlockedByFuriten, "劇本沒有走到「振聽擋掉榮和」的局面")
}

/// 食い替え劇本真的走到「副露後打牌」而且 libriichi 真的禁了那幾張嗎
///
/// 沒有這一條，`maskParityAgainstLibRiichi` 在食い替え這一段可能只是
/// 「兩邊都放行」——那等於沒驗到任何東西。這裡直接對 **libriichi 自己的輸出**斷言：
/// - 副露後打牌那一格，禁手索引全是 0（而且其他手上的牌還是 1，證明不是整排關掉）
/// - 下一次自家摸牌那一格，該放行的索引回到 1（證明禁手會解除，不是永久黏住）
@Test func kuikaeScenariosActuallyForbidTiles() {
    for (label, forbidden, stillAllowed, released) in kuikaeExpectations {
        guard let scenario = parityScenarios.first(where: { $0.label == label }) else {
            Issue.record("找不到劇本 \(label)")
            continue
        }
        let snapshots = runBoth(scenario.events, label: label)
        guard let meld = snapshots.first(where: { $0.label.contains("副露後打牌") }) else {
            Issue.record("[\(label)] 劇本沒有走到「副露後打牌」的時點")
            continue
        }

        for idx in forbidden {
            #expect(!meld.oracle.mask[idx],
                    "[\(label)] libriichi 在副露後仍允許打 index \(idx)（食い替え劇本失效）")
        }
        // 沒有禁過頭：這幾張手上有、規則沒禁，必須維持可打
        for idx in stillAllowed {
            #expect(meld.oracle.mask[idx],
                    "[\(label)] libriichi 在副露後把 index \(idx) 也禁了？劇本或預期寫錯了")
        }

        // 解除：副露打牌之後再摸一次牌，被禁的那幾張要回來
        guard let afterDraw = snapshots.last else {
            Issue.record("[\(label)] 沒有任何比對時點")
            continue
        }
        #expect(!afterDraw.label.contains("副露後打牌"),
                "[\(label)] 劇本結束在副露當下，沒有走到下一次自家摸牌")
        for idx in released {
            #expect(afterDraw.oracle.mask[idx],
                    "[\(label)] 下一次摸牌時 index \(idx) 仍被禁（食い替え沒有解除）")
        }
    }
}

/// `atFuriten` 只該影響 ch861 這一格
@Test func furitenFlagOnlyAffectsChannel861() {
    let state = PlayerState(playerId: 0)
    for json in furitenMissEvents.prefix(4) {
        guard let data = json.data(using: .utf8),
              let event = try? JSONDecoder().decode(MJAIEvent.self, from: data) else { continue }
        _ = state.update(event: event)
    }
    let before = ObsEncoder.encode(state: state).0
    state.atFuriten.toggle()
    let after = ObsEncoder.encode(state: state).0

    var touched: [Int] = []
    for ch in 0..<ObsEncoder.obsChannels {
        for i in 0..<34 where before[ch * 34 + i] != after[ch * 34 + i] {
            touched.append(ch)
            break
        }
    }
    #expect(touched == [furitenChannel], "atFuriten 影響的 channel 是 \(touched)，預期只有 \(furitenChannel)")
}

@Test func shantenAgainstLibRiichiCases() {
    /// "1111m 333p 222s 444z" → [(牌索引, 張數)]
    func parse(_ spec: String) -> [Int] {
        var t = [Int](repeating: 0, count: 34)
        let base = ["m": 0, "p": 9, "s": 18, "z": 27]
        for group in spec.split(separator: " ") {
            let chars = Array(group)
            guard let suit = base[String(chars[chars.count - 1])] else { continue }
            for c in chars.dropLast() {
                guard let n = c.wholeNumberValue else { continue }
                t[suit + n - 1] += 1
            }
        }
        return t
    }

    // 全部取自 libriichi 自己的 shanten.rs 測試
    let cases: [(String, Int, Int)] = [
        ("1111m 333p 222s 444z", 4, 1),
        ("147m 258p 369s 1234z", 4, 6),
        ("468m 33346p 7s", 3, 2),
        ("147m 258p 3s", 2, 4),
        ("4455s", 1, 0),
        ("7z", 0, 0),
        ("15559m 19p 19s 1234z", 4, 3),
        ("9999m 6677p 88s 355z", 4, 2),
        ("19m 19p 159s 123456z", 4, 1),
        ("2344456m 14p 127s 2z 7p", 4, 3),
        ("2344456m 14p 127s 2z 5p", 4, 2),
        ("344455667p 1139s 9m", 4, 2),
        ("344455667p 1139s 9p", 4, 1),
        ("122334m 678p 37s 22z 5s", 4, 0),
        ("122334m 678p 12s 22z 4s", 4, 0),
        ("12223456m 78889p 2m", 4, -1),
        ("34778p", 1, 0),
        ("34s", 0, 0),
        ("55m", 0, -1),
    ]

    var failures: [String] = []
    for (spec, lenDiv3, expected) in cases {
        let got = ShantenCalculator.calcAll(tehai: parse(spec), lenDiv3: lenDiv3)
        if got != expected {
            failures.append("\(spec) (lenDiv3=\(lenDiv3)): 期望 \(expected)，實得 \(got)")
        }
    }
    for f in failures { print("向聽不符: \(f)") }
    #expect(failures.isEmpty, "\(failures.count)/\(cases.count) 個案例與 libriichi 不符")
}

/// 對拍時實際踩到的案例：3 面子 + 雀頭 + 搭子。
///
/// 剪枝的下界若只樂觀估「還能湊幾組面子」、漏掉「剩下的牌還能湊搭子」，
/// 這手明明打 5m 就聽 4s/7s，會被算成一向聽——連帶讓立直判定與打牌分類整組錯掉。
@Test func shantenRegressionFromParity() {
    var t = [Int](repeating: 0, count: 34)
    for (idx, n) in [(0,2),(1,1),(2,1),(3,1),(13,1),(14,1),(15,1),(19,1),(20,1),(21,1),(22,1),(23,1)] {
        t[idx] = n
    }
    #expect(t.reduce(0,+) == 13)
    #expect(ShantenCalculator.calcAll(tehai: t, lenDiv3: 4) == 0, "1m1m 234m 567p 234s 5s6s 是聽牌")

    var complete = t
    complete[24] = 1
    #expect(ShantenCalculator.calcAll(tehai: complete, lenDiv3: 4) == -1, "補上 7s 是和了形")
}

// MARK: - 編碼延遲

/// 編碼延遲的上限（毫秒）
///
/// 只印數字不設門檻的量測擋不住任何回歸——效能變差三倍，測試照樣綠。
/// 所以這裡把「多慢算壞掉」寫成常數。
///
/// 數字怎麼來的（Apple Silicon，2026-08-02 實測，見 docs/decisions/implementation-notes.md）：
///
/// | 情境          | Debug 實測    | Release 實測 | 門檻 Debug | 門檻 Release |
/// |---------------|---------------|--------------|------------|--------------|
/// | 一般（聽牌）   | 3.2–3.5 ms    | 0.1 ms       | 60 ms      | 20 ms        |
/// | 最壞（三向聽） | 1194–1593 ms  | 36.9–52.4 ms | 5000 ms    | 250 ms       |
///
/// 門檻不是「剛好卡住現值」而是留了 3–200 倍餘裕，理由：期望值 DP 的耗時本來就
/// 隨機器與負載浮動（同一個 case 幾次量測之間差了 30%），門檻太緊會變成天天紅的
/// 雜訊，沒人會再認真看它。這裡要擋的是**數量級**的回歸——例如快取失效、
/// DP 記憶化被改壞、或不小心在迴圈裡重算整張表。
private enum LatencyBudget {
    #if DEBUG
    static let configuration = "Debug"
    static let typicalMs = 60.0
    static let worstCaseMs = 5_000.0
    #else
    static let configuration = "Release"
    static let typicalMs = 20.0
    static let worstCaseMs = 250.0
    #endif

    /// 慢機器的整體放寬倍率：`MORTALSWIFT_LATENCY_BUDGET_SCALE=3 swift test`
    ///
    /// 預設 1.0——門檻要能擋回歸就不能預設放水。這個旋鈕是給「機器不一樣」用的，
    /// 不是給「這次跑比較慢」用的。調大之前先確認不是自己剛把 encode 弄慢了。
    static var scale: Double {
        guard let raw = ProcessInfo.processInfo.environment["MORTALSWIFT_LATENCY_BUDGET_SCALE"],
              let value = Double(raw), value > 0
        else { return 1.0 }
        return value
    }

    static var typicalLimitMs: Double { typicalMs * scale }
    static var worstCaseLimitMs: Double { worstCaseMs * scale }
}

/// 單次 observation 編碼的耗時
///
/// 單人期望值推演是遞迴 + 記憶化的機率 DP，最壞情況很重。
/// 這東西要在對局中即時跑，所以延遲必須量出來，而且超標要**失敗**——
/// 只印數字的版本擋不住回歸。
@Test func encodeLatency() {
    let state = PlayerState(playerId: 0)
    for json in fullEvents {
        guard let data = json.data(using: .utf8),
              let event = try? JSONDecoder().decode(MJAIEvent.self, from: data) else { continue }
        _ = state.update(event: event)
    }

    // 暖身一次，避免把首次配置成本算進去
    _ = ObsEncoder.encode(state: state)

    let rounds = 5
    let start = DispatchTime.now().uptimeNanoseconds
    for _ in 0..<rounds { _ = ObsEncoder.encode(state: state) }
    let elapsed = DispatchTime.now().uptimeNanoseconds - start
    let msPerCall = Double(elapsed) / Double(rounds) / 1_000_000

    print("=== observation 編碼耗時（\(LatencyBudget.configuration)）===")
    print(String(format: "  每次 %.1f ms（%d 次平均）", msPerCall, rounds))
    print(String(format: "  門檻 %.1f ms", LatencyBudget.typicalLimitMs))
    print(String(format: "  向聽 %d，剩餘 %d 張", state.realTimeShanten(), state.tilesLeft))

    let typicalLimit = LatencyBudget.typicalLimitMs
    #expect(
        msPerCall <= typicalLimit,
        "編碼延遲回歸：\(msPerCall) ms > 門檻 \(typicalLimit) ms（\(LatencyBudget.configuration)）")
}

/// 最壞情況：開局、三向聽、牌山幾乎全滿——期望值 DP 的分支在這裡最多
@Test func encodeLatencyWorstCase() {
    let events: [String] = [
        #"{"type":"start_game","id":0,"names":["A","B","C","D"]}"#,
        // 散牌手：進張多、分支多
        #"{"type":"start_kyoku","bakaze":"E","dora_marker":"3s","kyoku":1,"honba":0,"kyotaku":0,"oya":0,"scores":[25000,25000,25000,25000],"tehais":[["1m","3m","5m","7m","9m","2p","4p","6p","8p","1s","3s","5s","7s"],["?","?","?","?","?","?","?","?","?","?","?","?","?"],["?","?","?","?","?","?","?","?","?","?","?","?","?"],["?","?","?","?","?","?","?","?","?","?","?","?","?"]]}"#,
        #"{"type":"tsumo","actor":0,"pai":"5p"}"#,
    ]
    let state = PlayerState(playerId: 0)
    for json in events {
        guard let data = json.data(using: .utf8),
              let event = try? JSONDecoder().decode(MJAIEvent.self, from: data) else { continue }
        _ = state.update(event: event)
    }

    let start = DispatchTime.now().uptimeNanoseconds
    _ = ObsEncoder.encode(state: state)
    let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000

    print("=== 最壞情況編碼耗時（\(LatencyBudget.configuration)）===")
    print(String(format: "  %.1f ms（門檻 %.1f ms）", ms, LatencyBudget.worstCaseLimitMs))
    print("  向聽 \(state.realTimeShanten())，剩餘 \(state.tilesLeft) 張")

    let worstLimit = LatencyBudget.worstCaseLimitMs
    #expect(
        ms <= worstLimit,
        "最壞情況編碼延遲回歸：\(ms) ms > 門檻 \(worstLimit) ms（\(LatencyBudget.configuration)）")
}

// MARK: - 編碼快取

/// 同一個狀態被連續問三次，encode 只能真的跑一次
///
/// Naki 的 `updateAvailableActions()` 就是這個形狀：先 `getMask()`、再
/// `getCandidateActions()`、推薦流程又問一次 `getMask()`。沒有快取時三次各跑一遍
/// 完整 encode（含最貴的期望值 DP），一次 UI 更新就疊出秒級延遲——而狀態根本沒動。
@Test func encodeIsCachedWithinOneStateRevision() async throws {
    let bot = try NativeMortalBot(playerId: 0, version: 4, useBundledModel: false)

    let events = [
        #"{"type":"start_game","id":0,"names":["P0","P1","P2","P3"]}"#,
        #"{"type":"start_kyoku","bakaze":"E","dora_marker":"3p","kyoku":1,"honba":0,"kyotaku":0,"oya":0,"scores":[25000,25000,25000,25000],"tehais":[["1m","2m","3m","4p","5p","6p","7s","8s","9s","E","S","W","N"],["?","?","?","?","?","?","?","?","?","?","?","?","?"],["?","?","?","?","?","?","?","?","?","?","?","?","?"],["?","?","?","?","?","?","?","?","?","?","?","?","?"]]}"#,
        #"{"type":"tsumo","actor":0,"pai":"P"}"#,
    ]
    for json in events {
        _ = try await bot.react(mjaiEvent: json)
    }

    let baseline = await bot.getEncodeCount()

    _ = await bot.getMask()
    _ = await bot.getCandidateActions()
    _ = await bot.getMask()
    _ = await bot.getObservation()

    let after = await bot.getEncodeCount()
    #expect(after == baseline, "狀態沒變卻重跑了 \(after - baseline) 次 encode")

    // 而且下一個事件必須讓快取失效——快取回舊張量比慢還糟
    _ = try await bot.react(
        mjaiEvent: #"{"type":"dahai","actor":0,"pai":"N","tsumogiri":false}"#)
    _ = await bot.getMask()
    let afterNextEvent = await bot.getEncodeCount()
    #expect(afterNextEvent > after, "事件進來之後快取沒有失效")
}

/// 快取回的張量必須和當場重算的位元相同
///
/// 這是快取唯一不可談判的性質：省時間可以，改數值不行。
/// 對拍測試證明的是 `ObsEncoder.encode` 對得上 libriichi；這裡證明的是
/// 走快取的那條路徑拿到的就是同一份東西。
@Test func cachedEncodingMatchesFreshEncode() async throws {
    let bot = try NativeMortalBot(playerId: 0, version: 4, useBundledModel: false)

    for json in fullEvents {
        _ = try? await bot.react(mjaiEvent: json)
    }

    let cachedObs = await bot.getObservation()
    let cachedMask = await bot.getMask()

    // 用同一串事件另外養一個狀態，直接呼叫 encode（不經過快取）
    let reference = PlayerState(playerId: 0)
    for json in fullEvents {
        guard let data = json.data(using: .utf8),
              let event = try? JSONDecoder().decode(MJAIEvent.self, from: data) else { continue }
        _ = reference.update(event: event)
    }
    let fresh = ObsEncoder.encode(state: reference)

    #expect(cachedObs == fresh.obs, "快取的 observation 與重算結果不同")
    #expect(cachedMask == fresh.mask, "快取的 mask 與重算結果不同")
}

// MARK: - Core ML 輸入搬運

/// memcpy 進 MLMultiArray 的每一格都要跟逐格裝箱時一樣
///
/// 換掉 `obsArray[i] = NSNumber(value:)` 是為了省掉 34,408 次裝箱，前提是
/// 搬進去的內容一模一樣。這裡拿真實形狀（1012×34 與 46）逐格比對——
/// 「模型還會給合理答案」不足以證明這件事，錯一小段照樣看起來正常。
@Test func memcpyIntoMLMultiArrayIsFaithful() throws {
    // 用可辨識的值，全 0 或全 1 會讓「根本沒搬」也通過
    let obsCount = NativeMortalBot.obsChannels * NativeMortalBot.obsWidth
    var values = [Float](repeating: 0, count: obsCount)
    for i in 0..<obsCount {
        values[i] = Float(i % 97) / 97.0
    }

    let array = try MLMultiArray(
        shape: [1, NSNumber(value: NativeMortalBot.obsChannels),
                NSNumber(value: NativeMortalBot.obsWidth)],
        dataType: .float32)
    try NativeMortalBot.copyFloats(values, into: array)

    var mismatches = 0
    for i in 0..<obsCount where array[i].floatValue != values[i] {
        mismatches += 1
    }
    #expect(mismatches == 0, "\(mismatches)/\(obsCount) 格與來源不同")

    // 遮罩那條路徑（UInt8 → Float）
    let mask: [UInt8] = (0..<NativeMortalBot.actionSpace).map { UInt8($0 % 2) }
    let maskArray = try MLMultiArray(
        shape: [1, NSNumber(value: NativeMortalBot.actionSpace)], dataType: .float32)
    try NativeMortalBot.copyFloats(mask.map(Float.init), into: maskArray)
    for i in 0..<NativeMortalBot.actionSpace {
        #expect(maskArray[i].floatValue == Float(mask[i]), "mask[\(i)] 搬錯")
    }

    // 長度對不上必須丟錯，不能默默搬一半
    #expect(throws: MortalError.self) {
        try NativeMortalBot.copyFloats([1, 2, 3], into: maskArray)
    }
}

/// 端到端合理性檢查：完整 observation 餵進模型後，推薦是不是合理的
///
/// 這**不是**強度評測——那需要跑幾千局的評測環境。
/// 這裡只驗一件事：在一個答案毫無爭議的局面上，模型有沒有給出那個答案。
/// 如果連這種局面都答錯，代表輸入管線還有問題。
@Test func botRecommendsObviousDiscard() async throws {
    let bot = try MortalBot(playerId: 0, version: 4, useBundledModel: true)
    guard await bot.hasModel else {
        Issue.record("模型不存在，無法做端到端檢查")
        return
    }

    // 123m 456m 789m 11p 44s + 摸到中。
    // 打中就是聽牌（1p/4s 雙碰），留中則毫無用處——這題沒有第二個答案。
    let events = [
        #"{"type":"start_game","id":0,"names":["P0","P1","P2","P3"]}"#,
        #"{"type":"start_kyoku","bakaze":"E","dora_marker":"9s","kyoku":1,"honba":0,"kyotaku":0,"oya":0,"scores":[25000,25000,25000,25000],"tehais":[["1m","2m","3m","4m","5m","6m","7m","8m","9m","1p","1p","4s","4s"],["?","?","?","?","?","?","?","?","?","?","?","?","?"],["?","?","?","?","?","?","?","?","?","?","?","?","?"],["?","?","?","?","?","?","?","?","?","?","?","?","?"]]}"#,
        #"{"type":"tsumo","actor":0,"pai":"C"}"#,
    ]

    var action: MJAIAction?
    for json in events {
        guard let data = json.data(using: .utf8),
              let event = try? JSONDecoder().decode(MJAIEvent.self, from: data) else { continue }
        action = try await bot.react(event: event)
    }

    // 合理答案有兩個：直接打中，或宣告立直（門前聽牌宣告立直是標準打法，
    // 而且立直本身就隱含把中打出去）。打掉已成面子的任何一張都是錯的。
    switch action {
    case .reach:
        break
    case .dahai(let dahai):
        #expect(dahai.pai == Tile(mjaiString: "C"), "該打的是中，實得 \(dahai.pai)")
    default:
        Issue.record("預期打牌或立直，實得 \(String(describing: action))")
    }
}

/// 副露之後必須還能推論
///
/// MJAI 協定在自己吃／碰／槓之後不會再送事件要你打牌，`react` 因此不會被呼叫。
/// 若呼叫端只能拿舊機率或退回均勻分布，那一手就完全沒有模型參與——
/// 實測 Naki 正是如此（log 裡的 `Using uniform probabilities`）。
/// `inferCurrentState()` 就是為了補這個洞。
@Test func inferCurrentStateWorksAfterMeld() async throws {
    let bot = try MortalBot(playerId: 0, version: 4, useBundledModel: true)
    guard await bot.hasModel else {
        Issue.record("模型不存在")
        return
    }

    let events = [
        #"{"type":"start_game","id":0,"names":["P0","P1","P2","P3"]}"#,
        #"{"type":"start_kyoku","bakaze":"E","dora_marker":"9s","kyoku":1,"honba":0,"kyotaku":0,"oya":0,"scores":[25000,25000,25000,25000],"tehais":[["1m","1m","2m","3m","4m","5m","6m","7m","1p","1p","4s","5s","C"],["?","?","?","?","?","?","?","?","?","?","?","?","?"],["?","?","?","?","?","?","?","?","?","?","?","?","?"],["?","?","?","?","?","?","?","?","?","?","?","?","?"]]}"#,
        #"{"type":"tsumo","actor":0,"pai":"9m"}"#,
        #"{"type":"dahai","actor":0,"pai":"C","tsumogiri":false}"#,
        #"{"type":"tsumo","actor":1,"pai":"?"}"#,
        // 上家打 3s，自己吃
        #"{"type":"dahai","actor":3,"pai":"3s","tsumogiri":false}"#,
        #"{"type":"chi","actor":0,"target":3,"pai":"3s","consumed":["4s","5s"]}"#,
    ]

    var lastAction: MJAIAction?
    for json in events {
        guard let data = json.data(using: .utf8),
              let event = try? JSONDecoder().decode(MJAIEvent.self, from: data) else { continue }
        lastAction = try await bot.react(event: event)
    }

    // 吃之後 react 回 nil——這正是問題所在
    #expect(lastAction == nil, "吃之後 MJAI 不會再要求動作")

    // 但直接推論必須拿得到結果
    let inferred = try await bot.inferCurrentState()
    #expect(inferred != nil, "副露後必須還能對當前狀態推論")

    // 而且機率要有差異，不能是均勻分布
    let probs = await bot.getLastProbs()
    let nonZero = probs.filter { $0 > 0 }
    #expect(nonZero.count > 1, "應該有多個合法動作")
    let allSame = nonZero.allSatisfy { abs($0 - nonZero[0]) < 1e-6 }
    #expect(!allSame, "機率全部相同代表沒有真的推論")
}
