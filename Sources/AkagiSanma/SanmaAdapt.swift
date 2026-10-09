/// 對應 `adapt.rs` 的 `enc_input_3p`：座位以 `seat` 為 0，依 `(seat + k) % 3` 旋轉。
extension SanmaState {
    public func encInput() -> SanmaEncInput {
        let me = players[seat]
        var e = SanmaEncInput()
        e.hand = me.hand
        e.drawnTile = drawnTile
        e.waits = Self.waits(me.hand, me.melds)
        e.isTenpai = !e.waits.isEmpty
        e.doraIndicators = doraIndicators
        // riichienv 的 mjai 重播路徑從不寫 riichi_sutehais、也不遞增 turn_count，Rust 推論與訓練時兩者恆為空／0。
        e.seats = (0..<3).map { k in
            let p = players[(seat + k) % 3]
            var s = SanmaSeat()
            s.discards = p.discards
            s.meldTiles = p.melds.flatMap(\.tiles)
            s.riichiDeclared = p.riichiDeclared
            s.score = Int32(clamping: p.score)
            s.kitaCount = UInt8(clamping: p.kitaCount)
            return s
        }
        e.lastDiscard = lastDiscard?.tile
        e.roundWind = UInt8(clamping: roundWind)
        e.seatWind = UInt8((seat + 3 - oya) % 3)
        e.honba = UInt8(clamping: honba)
        e.riichiSticks = UInt32(clamping: riichiSticks)
        e.isDealer = seat == oya
        e.kyokuIndex = UInt8(clamping: kyokuIndex)
        e.selfRiichi = me.riichiDeclared
        return e
    }
}
