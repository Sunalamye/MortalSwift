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

/// 一次比對結果
private struct ParitySnapshot {
    let label: String
    let oracle: (obs: [Float], mask: [Bool])
    let swift: (obs: [Float], mask: [Bool])
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

    for events in [minimalEvents, fullEvents] {
        let label = events.count == minimalEvents.count ? "minimal" : "full"
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
    for events in [minimalEvents, fullEvents] {
        let label = events.count == minimalEvents.count ? "minimal" : "full"
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
    for events in [minimalEvents, fullEvents] {
        let label = events.count == minimalEvents.count ? "minimal" : "full"
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
        _ = label
    }
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

/// 單次 observation 編碼的耗時
///
/// 單人期望值推演是遞迴 + 記憶化的機率 DP，最壞情況很重。
/// 這東西要在對局中即時跑，所以延遲必須量出來，不能只看正確性。
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

    print("=== observation 編碼耗時 ===")
    print(String(format: "  每次 %.1f ms（%d 次平均）", msPerCall, rounds))
    print(String(format: "  向聽 %d，剩餘 %d 張", state.realTimeShanten(), state.tilesLeft))
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

    print("=== 最壞情況編碼耗時 ===")
    print(String(format: "  %.1f ms", ms))
    print("  向聽 \(state.realTimeShanten())，剩餘 \(state.tilesLeft) 張")
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
