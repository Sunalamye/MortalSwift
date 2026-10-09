import Accelerate
import Foundation

/// Akagi 三麻 BC 模型（BN 已折疊）：conv_in + 3 殘差塊 + fc + head，純 Conv1d/Linear。
public struct SanmaModel: Sendable {
    public static let channels = 37
    public static let conv = 64
    public static let fcWidth = 256
    public static let actions = 60
    static let tiles = SanmaTiles.count

    struct Layer {
        let weight: [Float]
        let bias: [Float]
    }

    let convIn: Layer
    let res: [(Layer, Layer)]
    let fc: Layer
    let head: Layer

    public enum LoadError: Error, Equatable {
        case malformed(String)
        case missing(String)
        case shape(String, [Int])
    }

    public static func bundled() throws -> SanmaModel {
        guard let url = Bundle.module.url(forResource: "akagi3p", withExtension: "safetensors") else {
            throw LoadError.missing("akagi3p.safetensors")
        }
        return try SanmaModel(safetensors: Data(contentsOf: url))
    }

    public init(safetensors data: Data) throws {
        let bytes = [UInt8](data)
        guard bytes.count >= 8 else { throw LoadError.malformed("short file") }
        let headerLen = bytes[0..<8].enumerated().reduce(0) { $0 | Int($1.element) << (8 * $1.offset) }
        guard 8 + headerLen <= bytes.count,
              let header = try JSONSerialization.jsonObject(with: Data(bytes[8..<8 + headerLen])) as? [String: Any]
        else { throw LoadError.malformed("header") }
        let base = 8 + headerLen

        func tensor(_ key: String, _ shape: [Int]) throws -> [Float] {
            guard let info = header[key] as? [String: Any],
                  let offsets = info["data_offsets"] as? [Int], offsets.count == 2,
                  let dims = info["shape"] as? [Int]
            else { throw LoadError.missing(key) }
            guard info["dtype"] as? String == "F32", dims == shape,
                  offsets[1] - offsets[0] == shape.reduce(1, *) * 4,
                  base + offsets[1] <= bytes.count
            else { throw LoadError.shape(key, dims) }
            return bytes[(base + offsets[0])..<(base + offsets[1])].withUnsafeBytes { raw in
                (0..<raw.count / 4).map { Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: $0 * 4, as: UInt32.self))) }
            }
        }
        func layer(_ name: String, _ shape: [Int]) throws -> Layer {
            Layer(weight: try tensor("\(name).weight", shape), bias: try tensor("\(name).bias", [shape[0]]))
        }

        let c = Self.conv
        convIn = try layer("conv_in", [c, Self.channels, 3])
        res = try (0..<3).map { (try layer("res.\($0).conv1", [c, c, 3]), try layer("res.\($0).conv2", [c, c, 3])) }
        fc = try layer("fc", [Self.fcWidth, c * Self.tiles])
        head = try layer("head", [Self.actions, Self.fcWidth])
    }

    /// 輸入 channel-major `[37 × 27]`（buf[ch*27+tile]），輸出 60 個 logits。
    public func forward(_ obs: [Float]) -> [Float] {
        precondition(obs.count == Self.channels * Self.tiles, "obs 長度須為 \(Self.channels * Self.tiles)")
        var x = relu(conv1d(obs, convIn, inChannels: Self.channels))
        for (c1, c2) in res {
            let y = conv1d(relu(conv1d(x, c1, inChannels: Self.conv)), c2, inChannels: Self.conv)
            x = relu(zip(y, x).map(+))
        }
        let h = relu(linear(x, fc))
        return linear(h, head)
    }

    /// Conv1d(k=3, pad=1)：im2col 成 `[in*3 × T]` 後一次矩陣乘，權重 `[out, in, k]` 恰好對齊 in*3+k 列序。
    private func conv1d(_ x: [Float], _ l: Layer, inChannels: Int) -> [Float] {
        let t = Self.tiles
        var col = [Float](repeating: 0, count: inChannels * 3 * t)
        for ci in 0..<inChannels {
            for k in 0..<3 {
                let row = (ci * 3 + k) * t
                for i in 0..<t where (0..<t).contains(i + k - 1) {
                    col[row + i] = x[ci * t + i + k - 1]
                }
            }
        }
        let out = l.bias.count
        var y = [Float](repeating: 0, count: out * t)
        vDSP_mmul(l.weight, 1, col, 1, &y, 1, vDSP_Length(out), vDSP_Length(t), vDSP_Length(inChannels * 3))
        for o in 0..<out {
            for i in 0..<t { y[o * t + i] += l.bias[o] }
        }
        return y
    }

    private func linear(_ x: [Float], _ l: Layer) -> [Float] {
        var y = [Float](repeating: 0, count: l.bias.count)
        vDSP_mmul(l.weight, 1, x, 1, &y, 1, vDSP_Length(l.bias.count), 1, vDSP_Length(x.count))
        return zip(y, l.bias).map(+)
    }

    private func relu(_ v: [Float]) -> [Float] { v.map { max($0, 0) } }
}
