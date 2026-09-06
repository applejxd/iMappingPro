import XCTest
@testable import iMappingProCore

/// 深度バイナリの詰め直し・フォーマット検証（C-8）
final class DepthBinaryPackingTests: XCTestCase {

    // MARK: - Pixel Format

    func testSupportedDepthPixelFormat() {
        // kCVPixelFormatType_DepthFloat32 == 'fdep'
        XCTAssertTrue(DepthProcessor.isSupportedDepthPixelFormat(0x6664_6570))
    }

    func testUnsupportedDepthPixelFormats() {
        // 'hdep' (DepthFloat16) や BGRA は扱わない
        XCTAssertFalse(DepthProcessor.isSupportedDepthPixelFormat(0x6864_6570))
        XCTAssertFalse(DepthProcessor.isSupportedDepthPixelFormat(0x4247_5241))
        XCTAssertFalse(DepthProcessor.isSupportedDepthPixelFormat(0))
    }

    // MARK: - Packing

    func testDepthBinaryWithoutPadding() throws {
        let width = 4
        let height = 3
        let values: [Float] = (0..<(width * height)).map { Float($0) * 0.1 }

        let data = try XCTUnwrap(values.withUnsafeBytes { raw in
            DepthProcessor.depthBinary(
                source: raw.baseAddress!,
                width: width,
                height: height,
                bytesPerRow: width * 4
            )
        })

        let decoded = try XCTUnwrap(DepthProcessor.decodeDepthBinary(data))
        XCTAssertEqual(decoded.width, width)
        XCTAssertEqual(decoded.height, height)
        XCTAssertEqual(decoded.values, values)
    }

    func testDepthBinaryStripsRowPadding() throws {
        let width = 3
        let height = 2
        let bytesPerRow = 5 * 4 // 2 画素分のパディングを含む
        let floatsPerRow = bytesPerRow / 4

        // パディング領域には壊れた値を入れておく
        var source = [Float](repeating: -999, count: floatsPerRow * height)
        let expected: [Float] = [1, 2, 3, 4, 5, 6]
        for row in 0..<height {
            for column in 0..<width {
                source[row * floatsPerRow + column] = expected[row * width + column]
            }
        }

        let data = try XCTUnwrap(source.withUnsafeBytes { raw in
            DepthProcessor.depthBinary(
                source: raw.baseAddress!,
                width: width,
                height: height,
                bytesPerRow: bytesPerRow
            )
        })

        XCTAssertEqual(data.count, 8 + width * height * 4, "パディングは取り除かれる")
        let decoded = try XCTUnwrap(DepthProcessor.decodeDepthBinary(data))
        XCTAssertEqual(decoded.values, expected)
    }

    func testDepthBinaryRejectsTooSmallBytesPerRow() {
        let values = [Float](repeating: 1, count: 4)
        let result = values.withUnsafeBytes { raw in
            DepthProcessor.depthBinary(
                source: raw.baseAddress!,
                width: 4,
                height: 1,
                bytesPerRow: 4 // Float 1個分しかない
            )
        }
        XCTAssertNil(result, "bytesPerRow が行サイズ未満なら nil")
    }

    func testDepthBinaryRejectsEmptySize() {
        let values = [Float](repeating: 1, count: 4)
        values.withUnsafeBytes { raw in
            XCTAssertNil(DepthProcessor.depthBinary(
                source: raw.baseAddress!, width: 0, height: 1, bytesPerRow: 0
            ))
            XCTAssertNil(DepthProcessor.depthBinary(
                source: raw.baseAddress!, width: 1, height: 0, bytesPerRow: 4
            ))
        }
    }

    // MARK: - Valid Ratio

    func testDepthValidRatio() throws {
        let width = 2
        let height = 2
        let values: [Float] = [1.0, 0.0, 2.0, .nan]

        let data = try XCTUnwrap(values.withUnsafeBytes { raw in
            DepthProcessor.depthBinary(
                source: raw.baseAddress!,
                width: width,
                height: height,
                bytesPerRow: width * 4
            )
        })

        let ratio = try XCTUnwrap(DepthProcessor.depthValidRatio(binary: data))
        XCTAssertEqual(ratio, 0.5, accuracy: 0.0001, "0 と NaN は無効値")
    }

    func testDepthValidRatioRejectsBrokenData() {
        XCTAssertNil(DepthProcessor.depthValidRatio(binary: Data()))
        XCTAssertNil(DepthProcessor.depthValidRatio(binary: Data([0, 0, 0, 0])))
    }
}
