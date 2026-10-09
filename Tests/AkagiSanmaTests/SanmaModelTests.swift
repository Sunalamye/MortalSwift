import XCTest
@testable import AkagiSanma

final class SanmaModelTests: XCTestCase {
    struct Parity: Decodable {
        let C: Int, T: Int, input: [Float], logits: [Float], argmax: Int
    }

    func testParityWithPyTorchReference() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "parity_3p", withExtension: "json", subdirectory: "Fixtures"))
        let p = try JSONDecoder().decode(Parity.self, from: Data(contentsOf: url))
        XCTAssertEqual(p.C, SanmaModel.channels)
        XCTAssertEqual(p.T, SanmaTiles.count)

        let model = try SanmaModel.bundled()
        let got = model.forward(p.input)
        XCTAssertEqual(got.count, 60)
        let maxDiff = zip(got, p.logits).map { abs($0 - $1) }.max()!
        let argmax = got.indices.max { got[$0] < got[$1] }!
        print("parity_3p max|Δ| = \(maxDiff), argmax = \(argmax)")
        XCTAssertLessThan(maxDiff, 1e-4)
        XCTAssertEqual(argmax, p.argmax)

        let runs = 10
        let start = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<runs { _ = model.forward(p.input) }
        let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6 / Double(runs)
        print("forward avg over \(runs) runs = \(String(format: "%.3f", ms)) ms")
    }

    func testRejectsMalformedSafetensors() {
        XCTAssertThrowsError(try SanmaModel(safetensors: Data([1, 2, 3])))
        let header = Data(#"{"conv_in.weight":{"dtype":"F32","shape":[1],"data_offsets":[0,4]}}"#.utf8)
        var file = withUnsafeBytes(of: UInt64(header.count).littleEndian) { Data($0) }
        file.append(header)
        file.append(Data(count: 4))
        XCTAssertThrowsError(try SanmaModel(safetensors: file)) {
            XCTAssertEqual($0 as? SanmaModel.LoadError, .shape("conv_in.weight", [1]))
        }
    }
}
