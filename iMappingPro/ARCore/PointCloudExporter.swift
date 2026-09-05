import Foundation
#if canImport(simd)
import simd
#endif

// MARK: - ColorImage

/// センサ基準（ランドスケープ）で並んだ RGBA8 画像
struct ColorImage: Equatable {
    let width: Int
    let height: Int
    /// row-major の RGBA8 ピクセル列（`width * height * 4` バイト）
    let rgba: [UInt8]

    var isValid: Bool {
        width > 0 && height > 0 && rgba.count >= width * height * 4
    }

    /// 正規化座標 (0...1) の位置の色を取得する
    func sample(normalizedX: Float, normalizedY: Float) -> SIMD3<UInt8>? {
        guard isValid else { return nil }
        let x = Int((normalizedX * Float(width)).rounded(.down))
        let y = Int((normalizedY * Float(height)).rounded(.down))
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        let offset = (y * width + x) * 4
        return SIMD3<UInt8>(rgba[offset], rgba[offset + 1], rgba[offset + 2])
    }
}

// MARK: - ColoredPoint

/// 相対座標系上の色付き点
struct ColoredPoint: Equatable {
    var position: SIMD3<Float>
    var color: SIMD3<UInt8>
}

// MARK: - PointCloudExporter

/// RGB フレームと深度マップから色付き点群を生成し、PLY 形式へ書き出す
///
/// ARKit のシーン再構成メッシュ (`mesh.obj`) は色情報を持たないため、
/// テクスチャの代替として深度マップを逆投影した色付き点群を保存する。
enum PointCloudExporter {

    /// 逆投影に用いるカメラ内部パラメータ（カラー画像の解像度基準）
    struct Intrinsics: Equatable {
        let fx: Float
        let fy: Float
        let cx: Float
        let cy: Float
        /// 内部パラメータの基準となるカラー画像サイズ
        let imageWidth: Int
        let imageHeight: Int

        init(fx: Float, fy: Float, cx: Float, cy: Float, imageWidth: Int, imageHeight: Int) {
            self.fx = fx
            self.fy = fy
            self.cx = cx
            self.cy = cy
            self.imageWidth = imageWidth
            self.imageHeight = imageHeight
        }

        init(frame: PoseFrame) {
            self.init(
                fx: frame.focalLengthX,
                fy: frame.focalLengthY,
                cx: frame.principalPointX,
                cy: frame.principalPointY,
                imageWidth: frame.imageWidth,
                imageHeight: frame.imageHeight
            )
        }

        var isValid: Bool {
            fx > 0 && fy > 0 && imageWidth > 0 && imageHeight > 0
        }
    }

    /// 点群生成のパラメータ
    struct Options: Equatable {
        /// 深度マップを間引く間隔（1 で全画素）
        var pixelStride: Int = 2
        /// 採用する深度の下限（メートル）
        var minDepth: Float = 0.1
        /// 採用する深度の上限（メートル）
        var maxDepth: Float = 5.0

        init(pixelStride: Int = 2, minDepth: Float = 0.1, maxDepth: Float = 5.0) {
            self.pixelStride = pixelStride
            self.minDepth = minDepth
            self.maxDepth = maxDepth
        }
    }

    // MARK: - Unprojection

    /// 1 フレームの深度マップとカラー画像から相対座標系の色付き点群を生成する
    ///
    /// - Parameters:
    ///   - depth: `_depth.bin` をデコードした深度マップ（センサ基準）
    ///   - color: 同じフレームのカラー画像（センサ基準、無い場合は灰色になる）
    ///   - pose: 相対座標系におけるカメラ変換行列（カメラローカル → 相対座標系）
    ///   - intrinsics: カラー画像基準のカメラ内部パラメータ
    static func unproject(
        depth: DepthProcessor.DecodedDepthMap,
        color: ColorImage?,
        pose: simd_float4x4,
        intrinsics: Intrinsics,
        options: Options = Options()
    ) -> [ColoredPoint] {
        guard intrinsics.isValid, depth.width > 0, depth.height > 0 else { return [] }
        let stride = Swift.max(options.pixelStride, 1)
        let imageWidth = Float(intrinsics.imageWidth)
        let imageHeight = Float(intrinsics.imageHeight)
        let fallbackColor = SIMD3<UInt8>(180, 180, 180)

        var points: [ColoredPoint] = []
        points.reserveCapacity((depth.width / stride) * (depth.height / stride))

        for row in Swift.stride(from: 0, to: depth.height, by: stride) {
            for column in Swift.stride(from: 0, to: depth.width, by: stride) {
                let value = depth.values[row * depth.width + column]
                guard value.isFinite, value >= options.minDepth, value <= options.maxDepth else { continue }

                // 深度画素の中心を正規化座標へ（深度とカラーは同一 FOV・同一向き）
                let normalizedX = (Float(column) + 0.5) / Float(depth.width)
                let normalizedY = (Float(row) + 0.5) / Float(depth.height)

                // カラー画像基準のピクセル座標へ写してから逆投影する
                let pixelX = normalizedX * imageWidth
                let pixelY = normalizedY * imageHeight

                // ARKit のカメラ座標系: +X 右 / +Y 上 / -Z 前方（画像座標は +Y 下向き）
                let cameraX = (pixelX - intrinsics.cx) * value / intrinsics.fx
                let cameraY = -(pixelY - intrinsics.cy) * value / intrinsics.fy
                let cameraZ = -value

                let world = pose * SIMD4<Float>(cameraX, cameraY, cameraZ, 1)
                let sampled = color?.sample(normalizedX: normalizedX, normalizedY: normalizedY)
                points.append(
                    ColoredPoint(
                        position: SIMD3<Float>(world.x, world.y, world.z),
                        color: sampled ?? fallbackColor
                    )
                )
            }
        }
        return points
    }

    /// 総点数が上限を超えないような間引き間隔を求める
    static func pixelStride(
        depthWidth: Int,
        depthHeight: Int,
        frameCount: Int,
        maxPoints: Int,
        minimumStride: Int = 2
    ) -> Int {
        guard depthWidth > 0, depthHeight > 0, frameCount > 0, maxPoints > 0 else { return minimumStride }
        var stride = Swift.max(minimumStride, 1)
        while stride < 32 {
            let perFrame = (depthWidth / stride) * (depthHeight / stride)
            if perFrame * frameCount <= maxPoints { break }
            stride += 1
        }
        return stride
    }

    /// 全フレームから均等に `maxFrames` 件を選ぶためのフレーム間隔
    static func frameStride(frameCount: Int, maxFrames: Int) -> Int {
        guard frameCount > 0, maxFrames > 0 else { return 1 }
        return Swift.max(1, Int((Double(frameCount) / Double(maxFrames)).rounded(.up)))
    }

    // MARK: - PLY

    /// 色付き点群を PLY (binary little endian) へエンコードする
    static func plyData(points: [ColoredPoint]) -> Data {
        var header = "ply\n"
        header += "format binary_little_endian 1.0\n"
        header += "comment iMappingPro colored point cloud\n"
        header += "element vertex \(points.count)\n"
        header += "property float x\n"
        header += "property float y\n"
        header += "property float z\n"
        header += "property uchar red\n"
        header += "property uchar green\n"
        header += "property uchar blue\n"
        header += "end_header\n"

        var data = Data(header.utf8)
        data.reserveCapacity(data.count + points.count * 15)
        for point in points {
            for component in [point.position.x, point.position.y, point.position.z] {
                var bits = component.bitPattern.littleEndian
                withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
            }
            data.append(point.color.x)
            data.append(point.color.y)
            data.append(point.color.z)
        }
        return data
    }

    /// `plyData(points:)` が出力した PLY をデコードする
    static func decodePLY(_ data: Data) -> [ColoredPoint]? {
        let terminator = Data("end_header\n".utf8)
        guard let headerRange = data.range(of: terminator) else { return nil }
        let headerData = data.subdata(in: data.startIndex..<headerRange.lowerBound)
        guard let header = String(data: headerData, encoding: .utf8),
              header.hasPrefix("ply"),
              header.contains("format binary_little_endian 1.0") else { return nil }

        guard let countLine = header
            .split(separator: "\n")
            .first(where: { $0.hasPrefix("element vertex ") }),
            let count = Int(countLine.dropFirst("element vertex ".count).trimmingCharacters(in: .whitespaces))
        else { return nil }

        let bytesPerPoint = MemoryLayout<Float32>.size * 3 + 3
        let body = data.subdata(in: headerRange.upperBound..<data.endIndex)
        guard body.count >= count * bytesPerPoint else { return nil }

        var points: [ColoredPoint] = []
        points.reserveCapacity(count)
        body.withUnsafeBytes { raw in
            for i in 0..<count {
                let offset = i * bytesPerPoint
                let x = Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self)))
                let y = Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: offset + 4, as: UInt32.self)))
                let z = Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: offset + 8, as: UInt32.self)))
                let r = raw.loadUnaligned(fromByteOffset: offset + 12, as: UInt8.self)
                let g = raw.loadUnaligned(fromByteOffset: offset + 13, as: UInt8.self)
                let b = raw.loadUnaligned(fromByteOffset: offset + 14, as: UInt8.self)
                points.append(
                    ColoredPoint(position: SIMD3<Float>(x, y, z), color: SIMD3<UInt8>(r, g, b))
                )
            }
        }
        return points
    }
}

// MARK: - Frame Aggregation

#if canImport(UIKit)

extension PointCloudExporter {

    /// キーフレーム群（姿勢・カラー JPEG・深度バイナリ）から統合した色付き点群を生成する
    ///
    /// - Parameters:
    ///   - frames: 相対姿勢と内部パラメータ
    ///   - colorJPEGs: `frames` と同じ並びのカラー JPEG
    ///   - depthBinaries: `frames` と同じ並びの深度バイナリ（無い要素は nil）
    ///   - maxFrames: 使用するフレーム数の上限
    ///   - maxPoints: 生成する点数の上限（超えないよう画素を間引く）
    static func buildPointCloud(
        frames: [PoseFrame],
        colorJPEGs: [Data?],
        depthBinaries: [Data?],
        maxFrames: Int = 40,
        maxPoints: Int = 200_000
    ) -> [ColoredPoint] {
        guard !frames.isEmpty else { return [] }
        let step = frameStride(frameCount: frames.count, maxFrames: maxFrames)
        let selected = Swift.stride(from: 0, to: frames.count, by: step).map { $0 }

        let reference = frames.first { $0.depthWidth > 0 && $0.depthHeight > 0 }
        guard let reference else { return [] }
        let stride = pixelStride(
            depthWidth: reference.depthWidth,
            depthHeight: reference.depthHeight,
            frameCount: selected.count,
            maxPoints: maxPoints
        )
        let options = Options(pixelStride: stride)

        var points: [ColoredPoint] = []
        for index in selected {
            guard index < depthBinaries.count,
                  let depthData = depthBinaries[index],
                  let depthMap = DepthProcessor.decodeDepthBinary(depthData) else { continue }
            let frame = frames[index]
            let color = index < colorJPEGs.count
                ? colorJPEGs[index].flatMap { DepthProcessor.decodeSensorOrientedRGBA(jpeg: $0) }
                : nil
            points.append(
                contentsOf: unproject(
                    depth: depthMap,
                    color: color,
                    pose: CoordinateSystem.transform(from: frame),
                    intrinsics: Intrinsics(frame: frame),
                    options: options
                )
            )
            if points.count >= maxPoints { break }
        }
        return points
    }
}

#endif // canImport(UIKit)
