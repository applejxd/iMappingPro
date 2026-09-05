import XCTest
@testable import iMappingProCore

final class PointCloudExporterTests: XCTestCase {

    private func makeDepthMap(width: Int, height: Int, value: Float) -> DepthProcessor.DecodedDepthMap {
        DepthProcessor.DecodedDepthMap(
            width: width,
            height: height,
            values: [Float](repeating: value, count: width * height)
        )
    }

    private func makeIntrinsics() -> PointCloudExporter.Intrinsics {
        // 主点が画像中心、焦点距離は画像幅と同じ簡易カメラ
        PointCloudExporter.Intrinsics(
            fx: 100, fy: 100, cx: 50, cy: 50,
            imageWidth: 100, imageHeight: 100
        )
    }

    // MARK: - Unprojection

    func testUnprojectPlacesCenterPixelOnOpticalAxis() {
        let depth = makeDepthMap(width: 2, height: 2, value: 2.0)
        let points = PointCloudExporter.unproject(
            depth: depth,
            color: nil,
            pose: matrix_identity_float4x4,
            intrinsics: makeIntrinsics(),
            options: .init(pixelStride: 1)
        )
        XCTAssertEqual(points.count, 4)

        // 左上画素は光軸より左上（+X 側ではなく -X, +Y 側）にある
        let topLeft = points[0].position
        XCTAssertLessThan(topLeft.x, 0)
        XCTAssertGreaterThan(topLeft.y, 0)
        // カメラ前方は -Z
        XCTAssertEqual(topLeft.z, -2.0, accuracy: 1e-5)
    }

    func testUnprojectSkipsInvalidDepth() {
        var values = [Float](repeating: 1.0, count: 4)
        values[0] = 0            // 未計測
        values[1] = .nan         // 無効
        values[2] = 99           // 上限超過
        let depth = DepthProcessor.DecodedDepthMap(width: 2, height: 2, values: values)

        let points = PointCloudExporter.unproject(
            depth: depth,
            color: nil,
            pose: matrix_identity_float4x4,
            intrinsics: makeIntrinsics(),
            options: .init(pixelStride: 1)
        )
        XCTAssertEqual(points.count, 1)
    }

    func testUnprojectAppliesPoseTranslation() {
        var pose = matrix_identity_float4x4
        pose.columns.3 = SIMD4<Float>(1, 2, 3, 1)

        let points = PointCloudExporter.unproject(
            depth: makeDepthMap(width: 1, height: 1, value: 1.0),
            color: nil,
            pose: pose,
            intrinsics: makeIntrinsics(),
            options: .init(pixelStride: 1)
        )
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points[0].position.x, 1, accuracy: 1e-5)
        XCTAssertEqual(points[0].position.y, 2, accuracy: 1e-5)
        XCTAssertEqual(points[0].position.z, 2, accuracy: 1e-5)  // 3 - 1
    }

    func testUnprojectSamplesColor() {
        let color = ColorImage(
            width: 1,
            height: 1,
            rgba: [10, 20, 30, 255]
        )
        let points = PointCloudExporter.unproject(
            depth: makeDepthMap(width: 1, height: 1, value: 1.0),
            color: color,
            pose: matrix_identity_float4x4,
            intrinsics: makeIntrinsics(),
            options: .init(pixelStride: 1)
        )
        XCTAssertEqual(points.first?.color, SIMD3<UInt8>(10, 20, 30))
    }

    func testUnprojectRejectsInvalidIntrinsics() {
        let intrinsics = PointCloudExporter.Intrinsics(
            fx: 0, fy: 0, cx: 0, cy: 0, imageWidth: 0, imageHeight: 0
        )
        let points = PointCloudExporter.unproject(
            depth: makeDepthMap(width: 2, height: 2, value: 1),
            color: nil,
            pose: matrix_identity_float4x4,
            intrinsics: intrinsics
        )
        XCTAssertTrue(points.isEmpty)
    }

    // MARK: - Stride

    func testPixelStrideKeepsPointsUnderLimit() {
        let stride = PointCloudExporter.pixelStride(
            depthWidth: 256,
            depthHeight: 192,
            frameCount: 40,
            maxPoints: 200_000
        )
        let perFrame = (256 / stride) * (192 / stride)
        XCTAssertLessThanOrEqual(perFrame * 40, 200_000)
        XCTAssertGreaterThanOrEqual(stride, 2)
    }

    func testFrameStrideLimitsFrameCount() {
        let stride = PointCloudExporter.frameStride(frameCount: 200, maxFrames: 40)
        let selected = Array(Swift.stride(from: 0, to: 200, by: stride)).count
        XCTAssertLessThanOrEqual(selected, 40)
    }

    func testFrameStrideIsOneForSmallSessions() {
        XCTAssertEqual(PointCloudExporter.frameStride(frameCount: 10, maxFrames: 40), 1)
    }

    // MARK: - PLY Round Trip

    func testPLYHeaderAndRoundTrip() {
        let points = [
            ColoredPoint(position: SIMD3<Float>(1, 2, 3), color: SIMD3<UInt8>(255, 0, 0)),
            ColoredPoint(position: SIMD3<Float>(-0.5, 0.25, 10), color: SIMD3<UInt8>(0, 128, 255)),
        ]
        let data = PointCloudExporter.plyData(points: points)

        let header = String(data: data.prefix(200), encoding: .isoLatin1) ?? ""
        XCTAssertTrue(header.hasPrefix("ply\n"))
        XCTAssertTrue(header.contains("format binary_little_endian 1.0"))
        XCTAssertTrue(header.contains("element vertex 2"))

        let decoded = PointCloudExporter.decodePLY(data)
        XCTAssertEqual(decoded, points)
    }

    func testPLYRoundTripWithNoPoints() {
        let data = PointCloudExporter.plyData(points: [])
        XCTAssertEqual(PointCloudExporter.decodePLY(data), [])
    }

    func testDecodePLYRejectsInvalidData() {
        XCTAssertNil(PointCloudExporter.decodePLY(Data("not a ply".utf8)))
    }

    // MARK: - ColorImage

    func testColorImageSampleOutOfRangeReturnsNil() {
        let image = ColorImage(width: 1, height: 1, rgba: [1, 2, 3, 255])
        XCTAssertNil(image.sample(normalizedX: 1.5, normalizedY: 0.5))
        XCTAssertNil(image.sample(normalizedX: -0.1, normalizedY: 0.5))
    }

    func testColorImageInvalidBufferIsRejected() {
        let image = ColorImage(width: 4, height: 4, rgba: [0, 0, 0])
        XCTAssertFalse(image.isValid)
        XCTAssertNil(image.sample(normalizedX: 0.5, normalizedY: 0.5))
    }
}
