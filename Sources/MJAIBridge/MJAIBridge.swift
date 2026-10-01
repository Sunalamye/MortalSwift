//
//  MJAIBridge.swift
//  mjai-bridge CLI
//
//  mahjax ↔ MortalSwift 的 stdin/stdout JSON-lines 橋。
//  一個進程管 4 個 NativeMortalBot（座位 0–3），呼叫端負責視角遮蔽
//  （他家手牌/摸牌送 "?"）。
//
//  協定（每行一個 JSON，回應也是一行）：
//    {"seat":0,"event":{...mjai事件...}}  → {"ok":true,"seat":0,"action":<物件|null>}
//    {"cmd":"infer","seat":0}             → 同上（副露後 MJAI 不再送事件，主動補推論）
//    {"cmd":"ping"}                       → {"ok":true}（模型載入完成的就緒探針）
//    {"cmd":"quit"} 或 EOF                → 結束
//  錯誤回 {"ok":false,"error":"..."}，進程不退出。
//

import Foundation
import MortalSwift

@main
struct MJAIBridge {
    static func main() async {
        let bots: [NativeMortalBot]
        do {
            bots = try (0..<4).map { try NativeMortalBot(playerId: $0) }
        } catch {
            FileHandle.standardError.write(Data("mjai-bridge: bot init failed: \(error)\n".utf8))
            exit(1)
        }

        while let line = readLine(strippingNewline: true) {
            if line.isEmpty { continue }
            do {
                let reply = try await handle(line: line, bots: bots)
                write(reply)
            } catch {
                write(["ok": false, "error": "\(error)"])
            }
        }
    }

    enum BridgeError: Error, CustomStringConvertible {
        case badInput(String)
        var description: String {
            switch self { case .badInput(let msg): return msg }
        }
    }

    static func handle(line: String, bots: [NativeMortalBot]) async throws -> [String: Any] {
        guard let obj = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
            throw BridgeError.badInput("not a JSON object")
        }

        if let cmd = obj["cmd"] as? String {
            switch cmd {
            case "quit":
                exit(0)
            case "ping":
                return ["ok": true]
            case "infer":
                let seat = try seat(of: obj)
                let action = try await bots[seat].inferCurrentState()
                return try reply(seat: seat, actionJSON: action?.toJSONString())
            default:
                throw BridgeError.badInput("unknown cmd: \(cmd)")
            }
        }

        guard let event = obj["event"] as? [String: Any] else {
            throw BridgeError.badInput("missing event or cmd")
        }
        let seat = try seat(of: obj)
        let eventJSON = String(data: try JSONSerialization.data(withJSONObject: event), encoding: .utf8)!
        let actionJSON = try await bots[seat].react(mjaiEvent: eventJSON)
        return try reply(seat: seat, actionJSON: actionJSON)
    }

    static func seat(of obj: [String: Any]) throws -> Int {
        guard let seat = obj["seat"] as? Int, (0..<4).contains(seat) else {
            throw BridgeError.badInput("seat must be 0-3")
        }
        return seat
    }

    static func reply(seat: Int, actionJSON: String?) throws -> [String: Any] {
        var reply: [String: Any] = ["ok": true, "seat": seat]
        if let actionJSON {
            reply["action"] = try JSONSerialization.jsonObject(with: Data(actionJSON.utf8))
        } else {
            reply["action"] = NSNull()
        }
        return reply
    }

    static func write(_ obj: [String: Any]) {
        let data = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data("{\"ok\":false,\"error\":\"encode failed\"}".utf8)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}
