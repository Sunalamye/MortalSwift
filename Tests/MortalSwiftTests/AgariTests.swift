//
//  AgariTests.swift
//  MortalSwiftTests
//
//  和了判定的驗收。
//
//  所有案例逐字取自 libriichi `algo/agari.rs` 的 `mod test`——
//  那是唯一權威。Swift 版把查表換成執行期列舉（見 HandDivision.swift 的說明），
//  能不能通過這組案例，就是那個替換有沒有做對的判準。
//

import Testing

@testable import MortalSwift

/// 解析 libriichi 測試裡的手牌記法，例如 "2234455m 234p 234s 3m"
private func hand(_ spec: String) -> [Int] {
    var counts = [Int](repeating: 0, count: 34)
    let base = ["m": 0, "p": 9, "s": 18, "z": 27]
    for group in spec.split(separator: " ") {
        let chars = Array(group)
        guard let suit = base[String(chars[chars.count - 1])] else { continue }
        for c in chars.dropLast() {
            guard let n = c.wholeNumberValue, n >= 1, n <= 9 else { continue }
            counts[suit + n - 1] += 1
        }
    }
    return counts
}

// 牌索引常數，對應 libriichi 的 tu8!
private let E = 27, S = 28, W = 29, N = 30, P = 31, F = 32, C = 33
private func m(_ n: Int) -> Int { n - 1 }
private func p(_ n: Int) -> Int { 9 + n - 1 }
private func s(_ n: Int) -> Int { 18 + n - 1 }

@Test func agariAgainstLibRiichiCases() {
    // 2234455m 234p 234s + 3m 榮和：平和 + 三色 + 一盃口 ...
    #expect(AgariCalculator(
        tehai: hand("2234455m 234p 234s 3m"), isMenzen: true,
        bakaze: E, jikaze: S, winningTile: m(3), isRon: true
    ).searchYakus() == .normal(fu: 40, han: 4))

    // 立直 + 門前清自摸和（額外 2 飜），莊家
    let riichiTsumo = AgariCalculator(
        tehai: hand("12334m 345p 22s 777z 2m"), isMenzen: true,
        bakaze: E, jikaze: E, winningTile: m(3), isRon: false
    ).agari(additionalHans: 2, doras: 0)
    #expect(riichiTsumo?.point(isOya: true) == Point(ron: 7700, tsumoKo: 2600, tsumoOya: 0))

    // 七對子形（2255m 445p 667788s + 5p）
    let chitoi = AgariCalculator(
        tehai: hand("2255m 445p 667788s 5p"), isMenzen: true,
        bakaze: E, jikaze: S, winningTile: p(5), isRon: true
    ).searchYakus()
    #expect(chitoi == .normal(fu: 25, han: 3))
    #expect(chitoi?.point(isOya: false).ron == 3200)

    // 副露（兩個 234s 吃）
    #expect(AgariCalculator(
        tehai: hand("22334m 33p 4m"), isMenzen: false,
        chis: [s(2), s(2)],
        bakaze: E, jikaze: S, winningTile: m(4), isRon: true
    ).searchYakus() == .normal(fu: 30, han: 1))

    #expect(AgariCalculator(
        tehai: hand("223344p 667788s 3m 3m"), isMenzen: true,
        bakaze: S, jikaze: N, winningTile: m(3), isRon: false
    ).searchYakus() == .normal(fu: 30, han: 4))

    // 無役
    #expect(AgariCalculator(
        tehai: hand("234678m 1123488p 8p"), isMenzen: true,
        bakaze: E, jikaze: E, winningTile: p(8), isRon: true
    ).searchYakus() == nil)

    // 一盃口（無暗槓）
    #expect(AgariCalculator(
        tehai: hand("223344999m 1188p 8p"), isMenzen: true,
        bakaze: E, jikaze: E, winningTile: p(8), isRon: true
    ).searchYakus() == .normal(fu: 40, han: 1))

    // 一盃口（有暗槓——div 旗標不完整，走補救路徑）
    #expect(AgariCalculator(
        tehai: hand("223344m 1188p 8p"), isMenzen: true,
        ankans: [m(9)],
        bakaze: E, jikaze: E, winningTile: p(8), isRon: true
    ).searchYakus() == .normal(fu: 70, han: 1))

    // 四暗刻（自摸）→ 改成榮和變三暗刻 + 對對和
    #expect(AgariCalculator(
        tehai: hand("55566677m 11p 7m"), isMenzen: true,
        ankans: [s(9)],
        bakaze: E, jikaze: E, winningTile: m(7), isRon: false
    ).searchYakus() == .yakuman(1))
    #expect(AgariCalculator(
        tehai: hand("55566677m 11p 7m"), isMenzen: true,
        ankans: [s(9)],
        bakaze: E, jikaze: E, winningTile: m(7), isRon: true
    ).searchYakus() == .normal(fu: 80, han: 4))

    // 平和 + 二盃口 / 二盃口
    #expect(AgariCalculator(
        tehai: hand("666677778888m 99p"), isMenzen: true,
        bakaze: E, jikaze: E, winningTile: m(8), isRon: true
    ).searchYakus() == .normal(fu: 30, han: 4))
    #expect(AgariCalculator(
        tehai: hand("666677778888m 99p"), isMenzen: true,
        bakaze: E, jikaze: E, winningTile: m(7), isRon: true
    ).searchYakus() == .normal(fu: 40, han: 3))

    // 一氣通貫（門前 vs 副露）
    #expect(AgariCalculator(
        tehai: hand("12345678m 11p 9m"), isMenzen: true,
        ankans: [p(9)],
        bakaze: E, jikaze: E, winningTile: m(9), isRon: true
    ).searchYakus() == .normal(fu: 70, han: 2))
    #expect(AgariCalculator(
        tehai: hand("12345678m 11p 9m"), isMenzen: false,
        pons: [p(9)],
        bakaze: E, jikaze: E, winningTile: m(9), isRon: true
    ).searchYakus() == .normal(fu: 30, han: 1))

    // 門前清自摸和不計入 searchYakus
    #expect(AgariCalculator(
        tehai: hand("111222333m 67p 88s 8p"), isMenzen: true,
        bakaze: E, jikaze: E, winningTile: p(8), isRon: false
    ).searchYakus() == .normal(fu: 40, han: 2))

    // 字一色 + 四暗刻 + 大四喜 = 三倍役滿
    #expect(AgariCalculator(
        tehai: hand("1112223334447z 7z"), isMenzen: true,
        bakaze: E, jikaze: E, winningTile: C, isRon: true
    ).searchYakus() == .yakuman(3))

    // 純全帯幺九 + 三色同順（副露）
    #expect(AgariCalculator(
        tehai: hand("1m 789p 789s 1m"), isMenzen: false,
        chis: [m(7), s(1)],
        bakaze: E, jikaze: E, winningTile: m(1), isRon: false
    ).searchYakus() == .normal(fu: 30, han: 3))

    // 三暗刻（5s 是暗刻）
    #expect(AgariCalculator(
        tehai: hand("111444m 45556s 22z 5s"), isMenzen: true,
        bakaze: S, jikaze: S, winningTile: s(5), isRon: true
    ).searchYakus() == .normal(fu: 60, han: 2))

    // 混全帯幺九 + 役牌
    #expect(AgariCalculator(
        tehai: hand("999s 1777z 1z"), isMenzen: false,
        chis: [p(1)], pons: [N],
        bakaze: S, jikaze: S, winningTile: E, isRon: true
    ).searchYakus() == .normal(fu: 50, han: 2))

    // 混一色 + 混老頭 + 役牌×3 + 對對和 = 9 飜，符 70
    let mixed = AgariCalculator(
        tehai: hand("1119m 9m"), isMenzen: false,
        pons: [S, C], ankans: [N],
        bakaze: S, jikaze: N, winningTile: m(9), isRon: true)
    if case .normal(_, let han) = mixed.searchYakus() {
        #expect(han == 9)
    } else {
        Issue.record("預期為一般役 9 飜")
    }
    let (tile14, divs) = HandDecomposer.decompose(tehai: hand("1119m 9m"))
    let fu = divs.map { DivWorker(calc: mixed, tile14: tile14, div: $0).calcFu(hasPinfu: false) }.max()
    #expect(fu == 70)
}

/// 點數換算：libriichi `point.rs` 自己的測試把整張對照表化約成一條通式，
/// 這裡直接驗那條通式在所有 (符, 飜) 組合下都成立。
@Test func pointTableMatchesFormula() {
    for fu in stride(from: 20, through: 110, by: 10) + [25] {
        for han in 1...14 {
            if han == 1 && fu < 30 { continue }

            let base: Int
            switch han {
            case 13...: base = 8000
            case 11...12: base = 6000
            case 8...10: base = 4000
            case 6...7: base = 3000
            case 5: base = 2000
            default: base = min(fu * (1 << (2 + han)), 2000)
            }
            func expected(_ mult: Int) -> Int { (base * mult + 99) / 100 * 100 }

            let ko = Point.calc(isOya: false, fu: fu, han: han)
            #expect(ko.tsumoKo == expected(1), "\(fu)符\(han)飜 子自摸")
            #expect(ko.tsumoOya == expected(2), "\(fu)符\(han)飜 子自摸(莊付)")
            #expect(ko.ron == expected(4), "\(fu)符\(han)飜 子榮和")

            let oya = Point.calc(isOya: true, fu: fu, han: han)
            #expect(oya.tsumoKo == expected(2), "\(fu)符\(han)飜 莊自摸")
            #expect(oya.ron == expected(6), "\(fu)符\(han)飜 莊榮和")
        }
    }
}

private func + (lhs: StrideThrough<Int>, rhs: [Int]) -> [Int] {
    Array(lhs) + rhs
}
