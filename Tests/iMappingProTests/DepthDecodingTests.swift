import XCTest
@testable import iMappingProCore

final class DepthDecodingTests: XCTestCase {

    /// depthToBinary と同じフォーマットのテストデータを生成する
    private func makeDepthBinary(width: UInt32, height: UInt32, values: [Float]) -> Data {
        var data = Data()
        var w = width
        var h = height
        withUnsafeBytes(of: &w) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &h) { data.append(contentsOf: $0) }
        for value in values {
            var v = value
            withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
        }
        return data
    }

    // MARK: - Decode

    func testDecodeDepthBinary() throws {
        let data = makeDepthBinary(width: 2, height: 2, values: [0.5, 1.0, 1.5, 2.0])
        let map = try XCTUnwrap(DepthProcessor.decodeDepthBinary(data))
        XCTAssertEqual(map.width, 2)
        XCTAssertEqual(map.height, 2)
        XCTAssertEqual(map.values, [0.5, 1.0, 1.5, 2.0])
    }

    func testDecodeRejectsTruncatedPayload() {
        var data = makeDepthBinary(width: 2, height: 2, values: [0.5, 1.0, 1.5, 2.0])
        data.removeLast(4)
        XCTAssertNil(DepthProcessor.decodeDepthBinary(data))
    }

    func testDecodeRejectsTooShortHeader() {
        XCTAssertNil(DepthProcessor.decodeDepthBinary(Data([0x00, 0x01])))
    }

    func testDecodeRejectsZeroSize() {
        let data = makeDepthBinary(width: 0, height: 0, values: [])
        XCTAssertNil(DepthProcessor.decodeDepthBinary(data))
    }

    // MARK: - Range

    func testDepthRangeIgnoresInvalidValues() throws {
        let map = DepthProcessor.DecodedDepthMap(
            width: 2,
            height: 2,
            values: [0, Float.nan, 1.0, 3.0]
        )
        let range = try XCTUnwrap(DepthProcessor.depthRange(of: map))
        XCTAssertEqual(range.min, 1.0, accuracy: 0.0001)
        XCTAssertEqual(range.max, 3.0, accuracy: 0.0001)
    }

    func testDepthRangeIsNilWhenNoValidValues() {
        let map = DepthProcessor.DecodedDepthMap(width: 1, height: 2, values: [0, 0])
        XCTAssertNil(DepthProcessor.depthRange(of: map))
    }

    // MARK: - Colorization

    func testDepthRGBAPixelsMarksInvalidPixelsTransparent() {
        let map = DepthProcessor.DecodedDepthMap(width: 2, height: 1, values: [0, 2.0])
        let pixels = DepthProcessor.depthRGBAPixels(from: map)
        XCTAssertEqual(pixels.count, 2 * 4)
        XCTAssertEqual(pixels[3], 0)     // 無効値は透明
        XCTAssertEqual(pixels[7], 255)   // 有効値は不透明
    }

    func testDepthRGBAPixelsUsesNearRedFarBlue() {
        let map = DepthProcessor.DecodedDepthMap(width: 2, height: 1, values: [1.0, 5.0])
        let pixels = DepthProcessor.depthRGBAPixels(from: map)
        // 近距離は赤成分が強い
        XCTAssertGreaterThan(pixels[0], pixels[2])
        // 遠距離は青成分が強い
        XCTAssertGreaterThan(pixels[6], pixels[4])
    }

    func testTurboLikeColorClampsOutOfRangeInput() {
        XCTAssertEqual(DepthProcessor.turboLikeColor(-1).0, 255)
        XCTAssertEqual(DepthProcessor.turboLikeColor(2).2, 255)
    }
}
