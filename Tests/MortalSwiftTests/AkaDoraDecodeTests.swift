//
//  AkaDoraDecodeTests.swift
//  MortalSwiftTests
//
//  動作索引 34-36（打出紅五萬／筒／索）的解碼。
//
//  起因（scratchpad probe 實測）：`ObsEncoder` 會在 mask 34-36 設 1，
//  但 `ActionDecoder.decode` 只處理到 33，落到最後 `return nil`。
//  立直後摸紅五那種「唯一合法動作就是打紅五」的局面，decode 回 nil →
//  `react` 回 nil → 呼叫端當成「不需要動作」→ bot 靜默停手等到 server 逾時。
//
//  這個檔案把那支 probe 轉成正式測試。
//

import Foundation
import Testing

@testable import MortalSwift

// MARK: - 工具

private func parse(_ json: String) -> MJAIEvent? {
    guard let data = json.data(using: .utf8),
          let event = try? JSONDecoder().decode(MJAIEvent.self, from: data) else {
        Issue.record("事件解析失敗: \(json)")
        return nil
    }
    return event
}

/// 把 MJAI 事件字串餵進 PlayerState
@discardableResult
private func feed(_ state: PlayerState, _ events: [String]) -> Bool {
    var needsAction = false
    for json in events {
        guard let event = parse(json) else { continue }
        needsAction = state.update(event: event)
    }
    return needsAction
}

private func startKyoku(tehai: [String], oya: Int = 0, kyoku: Int = 1) -> String {
    let hand = tehai.map { "\"\($0)\"" }.joined(separator: ",")
    let hidden = #"["?","?","?","?","?","?","?","?","?","?","?","?","?"]"#
    return """
    {"type":"start_kyoku","bakaze":"E","dora_marker":"9m","kyoku":\(kyoku),"honba":0,\
    "kyotaku":0,"oya":\(oya),"scores":[25000,25000,25000,25000],\
    "tehais":[[\(hand)],\(hidden),\(hidden),\(hidden)]}
    """
}

private let startGame = #"{"type":"start_game","id":0,"names":["A","B","C","D"]}"#

private func dahaiOf(_ action: MJAIAction?) -> DahaiAction? {
    if case .dahai(let d) = action { return d }
    return nil
}

// MARK: - 34-36 必須解得出來

/// 三張紅五都在手上、而且各自是該花色唯一的五 → mask 只開 34/35/36，
/// decode 必須各自回對應的紅五打牌。
@Test func decodeAkaDiscardIndexes() {
    let state = PlayerState(playerId: 0)
    feed(state, [
        startGame,
        startKyoku(tehai: ["5mr", "5pr", "5sr", "1m", "2m", "3m", "1p", "2p", "3p",
                           "1s", "2s", "3s", "E"]),
        #"{"type":"tsumo","actor":0,"pai":"E"}"#,
    ])

    let mask = ObsEncoder.encode(state: state).1

    // 每個花色手上唯一的五都是紅五 → 普通五那格關掉、紅五那格打開
    #expect(mask[4] == 0 && mask[34] == 1, "五萬只有紅五：mask[4]=0、mask[34]=1")
    #expect(mask[13] == 0 && mask[35] == 1, "五筒只有紅五：mask[13]=0、mask[35]=1")
    #expect(mask[22] == 0 && mask[36] == 1, "五索只有紅五：mask[22]=0、mask[36]=1")

    let expected: [(Int, Tile)] = [
        (34, .man(5, red: true)),
        (35, .pin(5, red: true)),
        (36, .sou(5, red: true)),
    ]
    for (idx, tile) in expected {
        let action = ActionDecoder.decode(actionIdx: idx, state: state)
        guard let dahai = dahaiOf(action) else {
            Issue.record("decode(\(idx)) 應該是打牌，實得 \(String(describing: action))")
            continue
        }
        #expect(dahai.pai == tile, "decode(\(idx)) 應打 \(tile.mjaiString)，實得 \(dahai.pai.mjaiString)")
        #expect(dahai.actor == 0)
        // 摸進來的是 E，打紅五都是手切
        #expect(dahai.tsumogiri == false, "decode(\(idx)) 摸的是 E，打紅五不是摸切")
    }
}

/// 手上沒有那張紅五時，34-36 是無效索引
@Test func decodeAkaIndexWithoutAkaInHandIsNil() {
    let state = PlayerState(playerId: 0)
    feed(state, [
        startGame,
        startKyoku(tehai: ["5m", "5p", "5s", "1m", "2m", "3m", "1p", "2p", "3p",
                           "1s", "2s", "3s", "E"]),
        #"{"type":"tsumo","actor":0,"pai":"E"}"#,
    ])

    let mask = ObsEncoder.encode(state: state).1
    #expect(mask[34] == 0 && mask[35] == 0 && mask[36] == 0, "手上沒紅五，34-36 應全關")

    for idx in 34...36 {
        #expect(ActionDecoder.decode(actionIdx: idx, state: state) == nil,
                "手上沒紅五時 decode(\(idx)) 必須是 nil")
    }
}

// MARK: - probe 原案：立直後摸紅五

/// 立直成立後摸紅五：唯一合法動作是 index 34，而且 `react` 必須真的回這個打牌
///
/// 這就是實測停手的局面。修好之前：合法動作 index 只有 [34]、mask[4]=0、mask[34]=1，
/// 而 `decode(34)` 回 nil。
@Test func decodeAkaDiscardAfterRiichi() async throws {
    let events = [
        startGame,
        startKyoku(tehai: ["2m", "3m", "4m", "6m", "7m", "8m", "2p", "3p", "4p",
                           "5p", "5p", "7s", "8s"]),
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
        #"{"type":"tsumo","actor":0,"pai":"5mr"}"#,
    ]

    let state = PlayerState(playerId: 0)
    let needsAction = feed(state, events)
    #expect(needsAction, "立直後摸牌一定要打出去")

    let mask = ObsEncoder.encode(state: state).1
    let legal = (0..<mask.count).filter { mask[$0] == 1 }
    #expect(legal == [34], "立直後摸紅五，唯一合法動作是 34，實得 \(legal)")

    guard let dahai = dahaiOf(ActionDecoder.decode(actionIdx: 34, state: state)) else {
        Issue.record("decode(34) 回 nil —— bot 會在這裡停手")
        return
    }
    #expect(dahai.pai == .man(5, red: true))
    #expect(dahai.tsumogiri, "立直後只能摸切")

    // 端到端：react 不能回 nil（回 nil 就是呼叫端眼中的「不需要動作」）
    let bot = try MortalBot(playerId: 0, version: 4, useBundledModel: false)
    var action: MJAIAction?
    for json in events {
        guard let event = parse(json) else { continue }
        action = try await bot.react(event: event)
    }
    guard let reacted = dahaiOf(action) else {
        Issue.record("react 在「唯一合法動作是打紅五」時回了 \(String(describing: action))")
        return
    }
    #expect(reacted.pai == .man(5, red: true), "react 必須打出紅五")
    #expect(reacted.tsumogiri)
}

// MARK: - 摸切旗標

/// 摸紅五、手切普通五：不是摸切
///
/// 舊的判定是 `lastSelfTsumo?.deaka.index == actionIdx`，紅五 deaka 之後也是 4，
/// 於是「摸紅五、打普通五」被標成摸切。下游照摸切的位置抽牌，打出去的會是紅五——
/// 打錯牌，而且是打掉一張寶牌。
@Test func tsumogiriFlagDistinguishesAkaFromNormalFive() {
    let state = PlayerState(playerId: 0)
    feed(state, [
        startGame,
        // 不放 E 對子：摸進 5mr 會湊成 555m，配上對子就直接和了，mask 會多出和了那格
        startKyoku(tehai: ["5m", "5m", "1m", "2m", "3m", "1p", "2p", "3p",
                           "1s", "2s", "3s", "E", "S"]),
        #"{"type":"tsumo","actor":0,"pai":"5mr"}"#,
    ])

    let mask = ObsEncoder.encode(state: state).1
    #expect(mask[4] == 1 && mask[34] == 1, "手上有普通五也有紅五，兩格都要開")

    guard let normal = dahaiOf(ActionDecoder.decode(actionIdx: 4, state: state)),
          let aka = dahaiOf(ActionDecoder.decode(actionIdx: 34, state: state)) else {
        Issue.record("decode(4) / decode(34) 都應該是打牌")
        return
    }

    #expect(normal.pai == .man(5), "decode(4) 打的是普通五")
    #expect(normal.tsumogiri == false, "摸的是紅五，手切普通五不是摸切")

    #expect(aka.pai == .man(5, red: true), "decode(34) 打的是紅五")
    #expect(aka.tsumogiri, "摸紅五又打紅五才是摸切")
}

/// 反過來：手上有紅五、摸進普通五
@Test func tsumogiriFlagWhenDrawingNormalFiveHoldingAka() {
    let state = PlayerState(playerId: 0)
    feed(state, [
        startGame,
        startKyoku(tehai: ["5mr", "1m", "2m", "3m", "1p", "2p", "3p",
                           "1s", "2s", "3s", "E", "E", "S"]),
        #"{"type":"tsumo","actor":0,"pai":"5m"}"#,
    ])

    guard let normal = dahaiOf(ActionDecoder.decode(actionIdx: 4, state: state)),
          let aka = dahaiOf(ActionDecoder.decode(actionIdx: 34, state: state)) else {
        Issue.record("decode(4) / decode(34) 都應該是打牌")
        return
    }

    #expect(normal.pai == .man(5))
    #expect(normal.tsumogiri, "摸普通五、打普通五＝摸切")

    #expect(aka.pai == .man(5, red: true))
    #expect(aka.tsumogiri == false, "摸普通五卻打紅五＝手切")
}

// MARK: - 索引常量

/// `ActionIndex` 的 34-36 是紅五，不是「保留給三麻」
///
/// 註解寫錯不是無害的：下游照著「保留」去掃 mask，就會用 `prefix(discardEnd + 1)`
/// 把 34-36 切掉，看不到唯一的合法打牌。
@Test func actionIndexAkaConstantsArePartOfDiscardRange() {
    typealias AI = PlayerState.ActionIndex
    #expect(AI.akaDiscardMan5 == 34)
    #expect(AI.akaDiscardPin5 == 35)
    #expect(AI.akaDiscardSou5 == 36)
    #expect(AI.discardAkaEnd == 36, "含紅五的打牌範圍上界")
    #expect(AI.discardAkaEnd > AI.discardEnd, "紅五格在普通打牌範圍之外，掃 mask 不能只掃到 discardEnd")
    #expect(AI.discardAkaEnd + 1 == AI.riichi, "紅五格緊接在立直（37）之前")
}
