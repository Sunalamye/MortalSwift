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

        guard result == RIICHI_ACTION_REQUIRED else { return nil }
        return (obs, mask.map { $0 != 0 })
    }
}

// MARK: - 對拍

/// 一段能走到「輪到自己打牌」的最小事件序列
private let parityEvents: [String] = [
    #"{"type":"start_game","id":0,"names":["A","B","C","D"]}"#,
    #"{"type":"start_kyoku","bakaze":"E","dora_marker":"E","kyoku":1,"honba":0,"kyotaku":0,"oya":0,"scores":[25000,25000,25000,25000],"tehais":[["1m","2m","3m","4m","5m","6m","7m","8m","9m","1p","1p","1p","2s"],["?","?","?","?","?","?","?","?","?","?","?","?","?"],["?","?","?","?","?","?","?","?","?","?","?","?","?"],["?","?","?","?","?","?","?","?","?","?","?","?","?"]]}"#,
    #"{"type":"tsumo","actor":0,"pai":"5p"}"#,
]

/// 把同一串事件同時餵給 libriichi 與純 Swift，取最後一次需要動作時的 obs/mask
private func runBoth() -> (oracle: (obs: [Float], mask: [Bool]), swift: (obs: [Float], mask: [Bool]))? {
    guard let oracle = LibRiichiOracle(playerId: 0) else { return nil }
    let state = PlayerState(playerId: 0)

    var oracleResult: (obs: [Float], mask: [Bool])?
    var swiftResult: (obs: [Float], mask: [Bool])?

    for json in parityEvents {
        let compact = json
        if let r = oracle.update(compact) { oracleResult = r }

        if let data = compact.data(using: .utf8),
           let event = try? JSONDecoder().decode(MJAIEvent.self, from: data) {
            let needsAction = state.update(event: event)
            if needsAction {
                let encoded = ObsEncoder.encode(state: state)
                swiftResult = (encoded.0, encoded.1.map { $0 != 0 })
            }
        }
    }

    guard let o = oracleResult, let s = swiftResult else { return nil }
    return (o, s)
}

@Test func diagnoseParityPipeline() {
    guard let oracle = LibRiichiOracle(playerId: 0) else {
        print("oracle 建立失敗"); return
    }
    print("oracle shape: channels=\(oracle.channels) width=\(oracle.width)")
    let state = PlayerState(playerId: 0)
    for json in parityEvents {
        let compact = json
        let o = oracle.update(compact)
        var swiftNeeds = false
        var decoded = false
        if let data = compact.data(using: .utf8) {
            do {
                let event = try JSONDecoder().decode(MJAIEvent.self, from: data)
                decoded = true
                swiftNeeds = state.update(event: event)
            } catch {
                print("  decode 失敗: \(error)")
            }
        }
        print("event=\(compact.prefix(40))... oracle=\(o != nil ? "ACTION" : "none") swiftDecoded=\(decoded) swiftNeeds=\(swiftNeeds)")
    }
}

@Test func obsParityAgainstLibRiichi() throws {
    guard let (oracle, swift) = runBoth() else {
        Issue.record("無法取得雙方的 observation（事件序列未觸發動作或 oracle 建立失敗）")
        return
    }

    let width = 34
    let channels = ObsEncoder.obsChannels

    #expect(oracle.obs.count == swift.obs.count,
            "obs 長度必須一致：libriichi \(oracle.obs.count) vs swift \(swift.obs.count)")

    var mismatched: [Int] = []
    for ch in 0..<channels {
        for i in 0..<width {
            let idx = ch * width + i
            if oracle.obs[idx] != swift.obs[idx] {
                mismatched.append(ch)
                break
            }
        }
    }

    // 先量化落差，再談修正；這個數字就是 B 方案的工作量
    print("=== obs 對拍結果 ===")
    print("總 channels    : \(channels)")
    print("不一致 channels: \(mismatched.count)")
    if !mismatched.isEmpty {
        let preview = mismatched.prefix(40).map(String.init).joined(separator: ",")
        print("不一致索引(前40): \(preview)")
    }

    #expect(mismatched.isEmpty,
            "有 \(mismatched.count)/\(channels) 個 channel 與 libriichi 不一致")
}

@Test func maskParityAgainstLibRiichi() throws {
    guard let (oracle, swift) = runBoth() else {
        Issue.record("無法取得雙方的 mask")
        return
    }

    #expect(oracle.mask.count == swift.mask.count)

    var diff: [Int] = []
    for i in 0..<min(oracle.mask.count, swift.mask.count) where oracle.mask[i] != swift.mask[i] {
        diff.append(i)
    }

    print("=== mask 對拍結果 ===")
    print("不一致索引: \(diff)")
    print("libriichi : \(oracle.mask.map { $0 ? 1 : 0 })")
    print("swift     : \(swift.mask.map { $0 ? 1 : 0 })")

    #expect(diff.isEmpty, "mask 有 \(diff.count) 格與 libriichi 不一致")
}

@Test func dumpMismatchedChannels() {
    guard let (oracle, swift) = runBoth() else { return }
    let width = 34
    print("=== 逐 channel 落差明細 ===")
    var shown = 0
    for ch in 0..<ObsEncoder.obsChannels {
        let o = Array(oracle.obs[ch*width..<(ch+1)*width])
        let s = Array(swift.obs[ch*width..<(ch+1)*width])
        guard o != s else { continue }
        shown += 1
        if shown > 30 { print("... 其餘略"); break }
        let oNZ = o.enumerated().filter { $0.element != 0 }.map { "\($0.offset)=\($0.element)" }
        let sNZ = s.enumerated().filter { $0.element != 0 }.map { "\($0.offset)=\($0.element)" }
        print("ch\(ch): libriichi[\(oNZ.prefix(6).joined(separator: " "))] swift[\(sNZ.prefix(6).joined(separator: " "))]")
    }
}
