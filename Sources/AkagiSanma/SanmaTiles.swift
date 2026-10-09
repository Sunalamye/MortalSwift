/// 三麻牌索引。牌以 136 制 tid（0...135）表示，tile34 = tid / 4；赤五為 tid 16/52/88。
/// 三麻移除 2m–8m，張量用 27 格緊湊軸。
public enum SanmaTiles {
    public static let count = 27
    public static let akaTile34 = [4, 13, 22]

    /// tile34 → 緊湊索引；2m–8m 為 nil。
    public static let tile34ToCompact: [Int?] = (0..<34).map { t in
        switch t {
        case 0: 0
        case 1...7: nil
        default: t - 7
        }
    }

    public static func tile34(_ tid: UInt8) -> Int { Int(tid / 4) }

    public static func isAka(_ tid: UInt8) -> Bool { tid == 16 || tid == 52 || tid == 88 }

    /// tid 超出 0...135 時回傳 nil。
    public static func index(_ tid: UInt8) -> Int? { tid < 136 ? tile34ToCompact[tile34(tid)] : nil }

    /// 對應 riichienv `mjai_to_tid`：普通 5 取 copy 1、其他牌取 copy 0；`0m`／`5mr` 為赤五。
    public static func tid(mjai s: String) -> UInt8? {
        if let i = ["E", "S", "W", "N", "P", "F", "C"].firstIndex(of: s) { return UInt8(108 + i * 4) }
        switch s {
        case "5mr": return 16
        case "5pr": return 52
        case "5sr": return 88
        default: break
        }
        let c = Array(s)
        guard c.count >= 2, let n = c[0].wholeNumberValue else { return nil }
        if c[1] == "z" { return (1...7).contains(n) ? UInt8(108 + (n - 1) * 4) : nil }
        guard let suit = ["m", "p", "s"].firstIndex(of: c[1]) else { return nil }
        if n == 0 { return UInt8(suit * 36 + 16) }
        let base = suit * 36 + (n - 1) * 4
        return UInt8(n == 5 ? base + 1 : base)
    }

    /// 寶牌指示牌（tile34）→ 寶牌（tile34）；三麻萬子只剩 1m/9m，兩者互指。
    public static func nextDoraTile34(_ indicator: Int) -> Int {
        switch indicator {
        case 0: 8
        case 8: 0
        case 9...17: 9 + (indicator - 8) % 9
        case 18...26: 18 + (indicator - 17) % 9
        case 27...30: 27 + (indicator - 26) % 4
        case 31...33: 31 + (indicator - 30) % 3
        default: indicator
        }
    }
}
