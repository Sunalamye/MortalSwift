import XCTest
@testable import AkagiSanma

/// S1a 由 Akagi `native_bot::Engine`（cd68865、riichienv-core 0.4.8）逐事件 dump 的決策點，
/// 精簡格式見 Naki `.swfd/logs/s1b-sanma-state/compact_fixtures.py`。
/// Swift 和牌只看形狀，所以未經閘的合法集合可比 Rust 多出無役的 ron／tsumo；
/// 經 `decide(authorized:)`（授權 = Rust 合法集合的類別，模擬 oplist）後必須逐欄相等。
final class SanmaFixtureParityTests: XCTestCase {
    static let kinds: [String: SanmaAction.Kind] = [
        "Discard": .discard, "Chi": .chi, "Pon": .pon, "Daiminkan": .daiminkan, "Ankan": .ankan, "Kakan": .kakan,
        "Riichi": .riichi, "Ron": .ron, "Tsumo": .tsumo, "KyushuKyuhai": .kyushu, "Pass": .pass, "Kita": .kita,
    ]

    static func action(_ raw: Any) -> SanmaAction {
        let a = raw as! [Any]
        return SanmaAction(kinds[a[0] as! String]!, tile: (a[1] as? Int).map(UInt8.init), consumed: (a[2] as! [Int]).map(UInt8.init))
    }

    static func key(_ a: SanmaAction) -> String { "\(a.kind)/\(a.tile.map(String.init) ?? "-")/\(a.consumed)" }

    func testMatchesRustEngineAtEveryDecision() throws {
        let urls = try XCTUnwrap(Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: "Fixtures/s1a"))
        XCTAssertEqual(urls.count, 26)
        let model = try SanmaModel.bundled()
        var checked = 0, shapeOnlyExtras: [String] = [], extraWindows: [String] = [], mismatches: [String] = []
        var maxLogitDelta: Float = 0

        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let f = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            let seat = f["seat"] as! Int
            let decisions = Dictionary(uniqueKeysWithValues: (f["decisions"] as! [[String: Any]]).map { ($0["i"] as! Int, $0) })
            let engine = SanmaEngine(seat: seat, model: model)
            let name = url.deletingPathExtension().lastPathComponent

            for (i, line) in (f["events"] as! [String]).enumerated() {
                XCTAssertTrue(engine.feed(line: line), "\(name) event \(i)")
                let at = "\(name) event \(i)"
                let legal = engine.state.legalActions()
                guard let dec = decisions[i] else {
                    if !legal.isEmpty {
                        extraWindows.append("\(at): \(legal.map(Self.key))")
                        if !legal.allSatisfy({ $0.kind == .ron || $0.kind == .pass }) { mismatches.append("\(at): 多出非 ron 決策點 \(legal.map(Self.key))") }
                    }
                    continue
                }
                checked += 1
                func fail(_ field: String, _ detail: Any) { mismatches.append("\(at) [\(field)]: \(detail)") }

                let rustLegal = (dec["legal"] as! [Any]).map(Self.action)
                var extra = legal.map(Self.key)
                for k in rustLegal.map(Self.key) {
                    if let j = extra.firstIndex(of: k) { extra.remove(at: j) } else { fail("legal 缺少", k) }
                }
                if !extra.isEmpty {
                    if legal.filter({ extra.contains(Self.key($0)) }).allSatisfy({ $0.kind == .ron || $0.kind == .tsumo }) {
                        shapeOnlyExtras.append("\(at): \(extra)")
                    } else {
                        fail("legal 多出", extra)
                    }
                }

                var rustObs = [Float](repeating: 0, count: 999)
                for g in dec["obs"] as! [[Any]] {
                    for idx in g[1] as! [Int] { rustObs[idx] = Float((g[0] as! NSNumber).doubleValue) }
                }
                let obs = try XCTUnwrap(engine.state.encInput().encode())
                let obsDiff = obs.indices.filter { obs[$0] != rustObs[$0] }
                if !obsDiff.isEmpty { fail("obs", obsDiff.prefix(5).map { "ch\($0 / 27) t\($0 % 27) swift=\(obs[$0]) rust=\(rustObs[$0])" }) }

                let authorized = Set(rustLegal.map(\.kind))
                let gated = legal.filter { $0.kind == .discard || $0.kind == .pass || authorized.contains($0.kind) }
                if gated.map(Self.key).sorted() != rustLegal.map(Self.key).sorted() { fail("閘後 legal", gated.map(Self.key)) }
                let mask = SanmaActionCodec.legalMask(gated).indices.filter { SanmaActionCodec.legalMask(gated)[$0] }
                if mask != dec["mask"] as! [Int] { fail("mask", mask) }

                guard let d = engine.decide(authorized: authorized) else { fail("decide", "nil"); continue }
                let rustLogits = (dec["logits"] as! [NSNumber]).map(\.floatValue)
                let delta = zip(d.logits, rustLogits).map { abs($0 - $1) }.max() ?? .infinity
                maxLogitDelta = max(maxLogitDelta, delta)
                if delta > 1e-4 { fail("logits", delta) }
                if d.forced != dec["forced"] as! Bool { fail("forced", d.forced) }

                let rustRanked = dec["ranked"] as! [[Any]]
                let ranked = SanmaActionCodec.rank(gated, logits: d.logits)
                if ranked.count != rustRanked.count { fail("ranked 長度", ranked.count) }
                for (s, r) in zip(ranked, rustRanked) where SanmaActionCodec.index(s.action) != r[0] as? Int
                    || s.action != Self.action(r[1]) || abs(s.prob - (r[2] as! NSNumber).floatValue) > 1e-4 {
                    fail("ranked", "\(Self.key(s.action)) \(s.prob) vs \(r)")
                    break
                }

                var want = Self.action(rustRanked[0][1])
                if want.kind == .riichi { want.tile = (dec["reach_discard"] as? String).flatMap(SanmaTiles.tid(mjai:)) }
                if d.action != want { fail("action", "\(Self.key(d.action)) vs \(Self.key(want))") }
                if d.candidates.map(\.action).dropFirst() != ranked.prefix(SanmaEngine.topN).map(\.action).dropFirst() {
                    fail("candidates", d.candidates.map { Self.key($0.action) })
                }
            }
        }

        print("S1B-PARITY decisions=\(checked) maxLogitDelta=\(maxLogitDelta) shapeOnlyExtras=\(shapeOnlyExtras.count) extraWindows=\(extraWindows.count) mismatches=\(mismatches.count)")
        for line in shapeOnlyExtras { print("S1B-PARITY shape-only-extra \(line)") }
        for line in extraWindows { print("S1B-PARITY extra-window \(line)") }
        for line in mismatches.prefix(50) { print("S1B-PARITY mismatch \(line)") }
        XCTAssertEqual(checked, 1985)
        XCTAssertEqual(mismatches, [])
    }
}
