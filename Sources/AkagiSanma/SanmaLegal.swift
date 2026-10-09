import MortalSwift

/// 對應 riichienv `GameState3PLegalActions`，但和牌（tsumo／ron）只看形狀、不判役：役由上層 oplist 授權。
/// 每張實體牌各列一筆（同 tid 重複亦然），`forced` 依此計數。
extension SanmaState {
    public func legalActions() -> [SanmaAction] {
        guard !isDone else { return [] }
        switch phase {
        case .response:
            return activePlayers.contains(seat) ? (claims[seat] ?? []) + [SanmaAction(.pass)] : []
        case .act:
            return currentPlayer == seat ? turnActions() : []
        }
    }

    private func turnActions() -> [SanmaAction] {
        let me = players[seat]
        let hand = me.hand
        var legal: [SanmaAction] = []
        func allowed(_ t: UInt8) -> Bool { !me.forbidden.contains { $0 / 4 == t / 4 } }

        if let d = drawnTile, !me.riichiStage {
            var rest = hand
            if let i = rest.lastIndex(of: d) { rest.remove(at: i) }
            if Self.completes(rest, me.melds, with: d) { legal.append(SanmaAction(.tsumo, tile: d)) }
        }

        if me.riichiDeclared {
            if let d = drawnTile { legal.append(SanmaAction(.discard, tile: d)) }
        } else if me.riichiStage {
            legal += hand.filter { allowed($0) && Self.isTenpai(hand.removingFirst($0), me.melds) }
                .map { SanmaAction(.discard, tile: $0) }
        } else {
            legal += hand.filter(allowed).map { SanmaAction(.discard, tile: $0) }
            if me.score >= 1000, drawable > 0, me.melds.allSatisfy({ !$0.opened }),
               hand.indices.contains(where: { Self.isTenpai(hand.removing(at: $0), me.melds) }) {
                legal.append(SanmaAction(.riichi))
            }
        }

        if drawable > 0, let d = drawnTile {
            let counts = Self.counts(hand)
            if !me.riichiDeclared && !me.riichiStage {
                legal += (0..<34).filter { counts[$0] == 4 }.map(Self.ankan)
                for m in me.melds where m.kind == .pon {
                    legal += hand.filter { $0 / 4 == m.tiles[0] / 4 }.map { SanmaAction(.kakan, tile: $0, consumed: m.tiles) }
                }
            } else if me.riichiDeclared, counts[Int(d / 4)] == 4 {
                // 立直後暗槓不得改變聽牌。
                let kan = Self.ankan(Int(d / 4))
                let before = Self.waits(hand.removingFirst(d), me.melds)
                let after = Self.waits(hand.filter { $0 / 4 != d / 4 }, me.melds + [SanmaMeld(kind: .ankan, tiles: kan.consumed)])
                if !before.isEmpty && before == after { legal.append(kan) }
            }
        }

        // riichienv 的 mjai 重播路徑從不清 is_first_turn，所以只要沒人副露就一直可以九種九牌。
        if players.allSatisfy({ $0.melds.isEmpty }), !me.riichiStage,
           Set(hand.filter(Self.isYaochu).map { $0 / 4 }).count >= 9 {
            legal.append(SanmaAction(.kyushu))
        }

        if drawnTile != nil, drawable > 0 {
            legal += hand.filter { $0 / 4 == 30 }.map { SanmaAction(.kita, tile: $0) }
        }
        return legal
    }

    /// 對應 `_get_claim_actions_for_player`：三麻沒有吃。
    func claimActions(for i: Int, tile: UInt8) -> [SanmaAction] {
        let p = players[i]
        let kind = tile / 4
        var legal: [SanmaAction] = []
        if !p.discards.contains(where: { $0 / 4 == kind }) {
            let waits = Self.waits(p.hand, p.melds)
            let furiten = p.discards.contains { waits.contains($0 / 4) }
            if !furiten && Self.completes(p.hand, p.melds, with: tile) { legal.append(SanmaAction(.ron, tile: tile)) }
        }
        guard !p.riichiDeclared, drawable > 0 else { return legal }

        let matching = p.hand.filter { $0 / 4 == kind }
        if matching.count >= 2 && p.hand.count >= 3 {
            var seen: [[UInt8]] = []
            for a in matching.indices {
                for b in matching.indices where b > a && !seen.contains([matching[a], matching[b]]) {
                    let pair = [matching[a], matching[b]]
                    seen.append(pair)
                    // 食替禁止：碰完手上至少要留一張不同種的牌可打。
                    if p.hand.removingFirst(pair[0]).removingFirst(pair[1]).contains(where: { $0 / 4 != kind }) {
                        legal.append(SanmaAction(.pon, tile: tile, consumed: pair))
                    }
                }
            }
        }
        if matching.count >= 3 {
            legal.append(SanmaAction(.daiminkan, tile: tile, consumed: Array(matching.prefix(3))))
        }
        return legal
    }

    static func ankan(_ t34: Int) -> SanmaAction {
        let low = UInt8(t34 * 4)
        return SanmaAction(.ankan, tile: low, consumed: [low, low + 1, low + 2, low + 3])
    }

    static func isYaochu(_ tid: UInt8) -> Bool {
        let t = tid / 4
        return t >= 27 || t % 9 == 0 || t % 9 == 8
    }

    /// 槓子若在手內仍是 4 張則當 3 張計（riichienv `HandEvaluator3P::new` 的正規化）。
    static func counts(_ hand: [UInt8], _ melds: [SanmaMeld] = []) -> [Int] {
        var c = [Int](repeating: 0, count: 34)
        for t in hand where t < 136 { c[Int(t / 4)] += 1 }
        for m in melds where m.kind == .daiminkan || m.kind == .ankan || m.kind == .kakan {
            let t = Int(m.tiles[0] / 4)
            if c[t] == 4 { c[t] = 3 }
        }
        return c
    }

    /// 任一種超過 4 張（例如他家 `?` 被當成 tid 0）時直接判否：ShantenTable 以 unsafe 指標查表，會越界。
    static func isAgari(_ c: [Int]) -> Bool {
        let n = c.reduce(0, +)
        guard n % 3 == 2, c.allSatisfy({ $0 <= 4 }) else { return false }
        if n == 14 && (ShantenCalculator.calcChitoi(tehai: c) == -1 || ShantenCalculator.calcKokushi(tehai: c) == -1) {
            return true
        }
        return ShantenCalculator.calcNormal(tehai: c, lenDiv3: n / 3) == -1
    }

    /// 待牌（tile34 升冪）；手牌加副露不是 13 張時為空，所以自家摸牌後恆為空。
    static func waits(_ hand: [UInt8], _ melds: [SanmaMeld]) -> [UInt8] {
        var c = counts(hand, melds)
        guard c.reduce(0, +) + melds.count * 3 == 13 else { return [] }
        var waits: [UInt8] = []
        for t in 0..<34 where c[t] < 4 {
            c[t] += 1
            if isAgari(c) { waits.append(UInt8(t)) }
            c[t] -= 1
        }
        return waits
    }

    static func isTenpai(_ hand: [UInt8], _ melds: [SanmaMeld]) -> Bool { !waits(hand, melds).isEmpty }

    /// 對應 `HandEvaluator3P::calc` 的成和形狀判定：手牌加副露為 13 張時才把 `tile` 加進來。
    static func completes(_ hand: [UInt8], _ melds: [SanmaMeld], with tile: UInt8) -> Bool {
        var c = counts(hand, melds)
        if c.reduce(0, +) + melds.count * 3 == 13, tile < 136 { c[Int(tile / 4)] += 1 }
        return isAgari(c)
    }
}

extension Array where Element == UInt8 {
    func removingFirst(_ t: UInt8) -> [UInt8] {
        var a = self
        if let i = a.firstIndex(of: t) { a.remove(at: i) }
        return a
    }

    func removing(at i: Int) -> [UInt8] {
        var a = self
        a.remove(at: i)
        return a
    }
}
