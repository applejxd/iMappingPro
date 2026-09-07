#if canImport(ARKit)
import ARKit
#endif
#if canImport(CoreVideo)
import CoreVideo
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(simd)
import simd
#endif
import Foundation

/// 深度データ（CVPixelBuffer）の処理・変換を担当
final class DepthProcessor {

    #if canImport(CoreVideo)
    // MARK: - Depth Binary Format

    /// Float32 深度マップを独自バイナリ形式に変換する
    /// フォーマット: [UInt32 width][UInt32 height][Float32 * width * height]
    ///
    /// ピクセルフォーマットが Float32 深度でない場合は nil を返す。
    /// 行パディング（`bytesPerRow` > `width * 4`）がある場合も行単位でコピーして詰める。
    static func depthToBinary(pixelBuffer: CVPixelBuffer) -> Data? {
        guard isSupportedDepthPixelFormat(CVPixelBufferGetPixelFormatType(pixelBuffer)) else {
            return nil
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }

        return depthBinary(
            source: baseAddress,
            width: width,
            height: height,
            bytesPerRow: bytesPerRow
        )
    }

    /// 信頼度マップを PNG 用 Data に変換する（UInt8 グレースケール）
    static func confidenceToData(pixelBuffer: CVPixelBuffer) -> Data? {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_OneComponent8 else {
            return nil
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard width > 0, height > 0, bytesPerRow >= width else { return nil }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }

        // UInt8 の各値をグレースケール値にマッピング（0=0, 1=127, 2=254）
        var pixels = [UInt8](repeating: 0, count: width * height)
        for row in 0..<height {
            let rowPtr = baseAddress.advanced(by: row * bytesPerRow).assumingMemoryBound(to: UInt8.self)
            for column in 0..<width {
                let level = min(Int(rowPtr[column]), 2)
                pixels[row * width + column] = UInt8(level * 127)
            }
        }

        // CGImage 経由で PNG Data を作成
        return createGrayscalePNG(pixels: pixels, width: width, height: height)
    }

    /// 信頼度マップの平均レベル (0...2) を求める
    static func confidenceMean(pixelBuffer: CVPixelBuffer) -> Float? {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_OneComponent8 else {
            return nil
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard width > 0, height > 0, bytesPerRow >= width else { return nil }
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }

        var total = 0
        for row in 0..<height {
            let rowPtr = baseAddress.advanced(by: row * bytesPerRow).assumingMemoryBound(to: UInt8.self)
            for column in 0..<width {
                total += min(Int(rowPtr[column]), 2)
            }
        }
        return Float(total) / Float(width * height)
    }

    /// RGB フレームを JPEG Data に変換する（YCbCr → UIImage 経由）
    ///
    /// ARKit の `capturedImage` はセンサ基準（ランドスケープ）で格納されているため、
    /// ピクセル配列はそのままに EXIF の向き（`.right` = 時計回り 90°）だけを付与する。
    /// これにより縦持ちで撮影した画像が各種ビューアで正立し、
    /// `poses.json` の内部パラメータ（センサ基準）との整合も保たれる。
    static func colorToJPEGData(
        pixelBuffer: CVPixelBuffer,
        quality: CGFloat = 0.9,
        orientation: UIImage.Orientation = captureImageOrientation
    ) -> Data? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        let uiImage = UIImage(cgImage: cgImage, scale: 1, orientation: orientation)
        return uiImage.jpegData(compressionQuality: quality)
    }
    #endif

    #if canImport(UIKit)
    /// センサ基準の画像を縦持ち（ポートレート）で正立表示するための向き
    ///
    /// ARKit のカメラ画像は横長（ランドスケープ）で取得されるため、
    /// ポートレート UI では時計回りに 90° 回転させる必要がある。
    static let captureImageOrientation: UIImage.Orientation = .right
    #endif

    // MARK: - Depth Binary Decoding

    /// Float32 深度の CVPixelBuffer フォーマット (`kCVPixelFormatType_DepthFloat32`)
    ///
    /// CoreVideo が使えない環境でも参照できるよう生値で保持する。
    static let depthFloat32PixelFormat: UInt32 = 0x6664_6570 // 'fdep'

    /// `depthToBinary` が扱える深度フォーマットかどうか
    static func isSupportedDepthPixelFormat(_ rawValue: UInt32) -> Bool {
        rawValue == depthFloat32PixelFormat
    }

    /// Float32 深度の生バッファを行パディングを除いた独自バイナリ形式へ詰め直す
    ///
    /// フォーマット: [UInt32 width][UInt32 height][Float32 * width * height]
    static func depthBinary(
        source: UnsafeRawPointer,
        width: Int,
        height: Int,
        bytesPerRow: Int
    ) -> Data? {
        guard width > 0, height > 0 else { return nil }
        let (rowBytes, rowBytesOverflow) = width.multipliedReportingOverflow(
            by: MemoryLayout<Float32>.size
        )
        guard !rowBytesOverflow, bytesPerRow >= rowBytes else { return nil }

        let (payloadBytes, payloadOverflow) = rowBytes.multipliedReportingOverflow(by: height)
        guard !payloadOverflow else { return nil }

        let headerBytes = MemoryLayout<UInt32>.size * 2
        let (totalBytes, totalBytesOverflow) = headerBytes.addingReportingOverflow(payloadBytes)
        guard !totalBytesOverflow else { return nil }

        var data = Data(capacity: totalBytes)
        // ヘッダ: width, height (UInt32)
        var w = UInt32(width)
        var h = UInt32(height)
        withUnsafeBytes(of: &w) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &h) { data.append(contentsOf: $0) }

        // 深度値 (Float32) を行単位でコピーしてパディングを取り除く
        var rowPointer = source
        for _ in 0..<height {
            data.append(contentsOf: UnsafeBufferPointer(
                start: rowPointer.assumingMemoryBound(to: UInt8.self),
                count: rowBytes
            ))
            rowPointer = rowPointer.advanced(by: bytesPerRow)
        }
        return data
    }

    /// `_depth.bin` の有効画素率 (0...1) を求める
    static func depthValidRatio(binary data: Data) -> Float? {
        let headerSize = MemoryLayout<UInt32>.size * 2
        guard data.count >= headerSize else { return nil }

        let width = Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: UInt32.self) })
        let height = Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self) })
        let (pixelCount, overflow) = width.multipliedReportingOverflow(by: height)
        guard width > 0, height > 0, !overflow else { return nil }

        let (payloadSize, payloadOverflow) = pixelCount.multipliedReportingOverflow(
            by: MemoryLayout<Float32>.size
        )
        guard !payloadOverflow, data.count >= headerSize + payloadSize else { return nil }

        let validCount = data.withUnsafeBytes { raw in
            var count = 0
            for index in 0..<pixelCount {
                let value = raw.loadUnaligned(
                    fromByteOffset: headerSize + index * MemoryLayout<Float32>.size,
                    as: Float32.self
                )
                if value.isFinite && value > 0 { count += 1 }
            }
            return count
        }
        return Float(validCount) / Float(pixelCount)
    }

    /// `_depth.bin` をデコードした結果
    struct DecodedDepthMap: Equatable {
        let width: Int
        let height: Int
        /// row-major の深度値（メートル）。0 および NaN は無効値
        let values: [Float]
    }

    /// `depthToBinary` が出力したバイナリをデコードする
    static func decodeDepthBinary(_ data: Data) -> DecodedDepthMap? {
        let headerSize = MemoryLayout<UInt32>.size * 2
        guard data.count >= headerSize else { return nil }

        let width = Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: UInt32.self) })
        let height = Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self) })
        guard width > 0, height > 0 else { return nil }

        let expectedBytes = width * height * MemoryLayout<Float32>.size
        guard data.count >= headerSize + expectedBytes else { return nil }

        var values = [Float](repeating: 0, count: width * height)
        data.withUnsafeBytes { raw in
            for i in 0..<(width * height) {
                values[i] = raw.loadUnaligned(
                    fromByteOffset: headerSize + i * MemoryLayout<Float32>.size,
                    as: Float32.self
                )
            }
        }
        return DecodedDepthMap(width: width, height: height, values: values)
    }

    /// 有効な深度値の最小・最大を求める（無効値は無視）
    static func depthRange(of map: DecodedDepthMap) -> (min: Float, max: Float)? {
        var minValue = Float.greatestFiniteMagnitude
        var maxValue = -Float.greatestFiniteMagnitude
        for value in map.values where value.isFinite && value > 0 {
            minValue = Swift.min(minValue, value)
            maxValue = Swift.max(maxValue, value)
        }
        guard minValue <= maxValue else { return nil }
        return (minValue, maxValue)
    }

    /// 深度マップを可視化用の RGBA ピクセル列へ変換する（近い=赤、遠い=青のカラーマップ）
    ///
    /// 無効値（0 / NaN）は透明ピクセルになる。
    static func depthRGBAPixels(from map: DecodedDepthMap) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: map.width * map.height * 4)
        guard let range = depthRange(of: map) else { return pixels }

        let span = Swift.max(range.max - range.min, 0.0001)
        for (i, value) in map.values.enumerated() {
            guard value.isFinite, value > 0 else { continue }
            let normalized = Swift.min(Swift.max((value - range.min) / span, 0), 1)
            let color = turboLikeColor(normalized)
            let offset = i * 4
            pixels[offset] = color.0
            pixels[offset + 1] = color.1
            pixels[offset + 2] = color.2
            pixels[offset + 3] = 255
        }
        return pixels
    }

    /// 正規化値 (0...1) を近距離=赤 → 遠距離=青 のカラーへ変換する
    static func turboLikeColor(_ normalized: Float) -> (UInt8, UInt8, UInt8) {
        // HSV の色相 0°(赤) → 240°(青) を線形補間した簡易カラーマップ
        let hue = Swift.min(Swift.max(normalized, 0), 1) * 240.0 / 360.0
        let sector = hue * 6
        let index = Int(sector) % 6
        let fraction = sector - Float(Int(sector))
        let q = 1 - fraction
        let t = fraction

        let rgb: (Float, Float, Float)
        switch index {
        case 0: rgb = (1, t, 0)
        case 1: rgb = (q, 1, 0)
        case 2: rgb = (0, 1, t)
        case 3: rgb = (0, q, 1)
        default: rgb = (0, 0, 1)
        }
        return (
            UInt8((rgb.0 * 255).rounded()),
            UInt8((rgb.1 * 255).rounded()),
            UInt8((rgb.2 * 255).rounded())
        )
    }

    // MARK: - Key Frame Selection

    private var lastTranslation: SIMD3<Float> = .zero
    private var lastQuaternion: simd_quatf = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
    private var lastTimestamp: TimeInterval = 0

    /// 直前に評価した（採用したとは限らない）フレームの姿勢
    ///
    /// 姿勢の不連続はキーフレーム間隔ではなくフレーム間隔で判定する必要があるため、
    /// 採用時のみ更新する `last*` とは別に保持する。
    private var previousObservation: (translation: SIMD3<Float>, quaternion: simd_quatf, timestamp: TimeInterval)?

    let minTranslationDistance: Float = 0.05  // 5cm
    let minRotationAngle: Float = 0.05        // ~3°
    let maxFrameInterval: TimeInterval = 1.0  // 最大1秒

    /// 物理的にあり得る並進速度の上限 (m/s)
    ///
    /// 手持ちスキャンで到達し得ない速度。これを超える変化はワールド原点の
    /// リセットや再ローカライズによる姿勢の飛びとみなす。
    static let maxTranslationSpeed: Float = 5.0
    /// 物理的にあり得る回転速度の上限 (rad/s) ≈ 400°/s
    static let maxRotationSpeed: Float = 7.0
    /// フレーム間隔の測定誤差を吸収する許容量
    static let motionToleranceTranslation: Float = 0.05  // 5cm
    static let motionToleranceRotation: Float = 0.10     // ~5.7°

    /// キーフレーム判定の結果
    enum CaptureDecision: Equatable {
        /// キーフレームとして採用する
        case capture
        /// 閾値未満・低品質のため見送る
        case skip
        /// 姿勢が不連続なので破棄し、トラッキング再初期化として扱う
        case discontinuity
    }

    /// フレーム間の姿勢変化が物理的に妥当かどうかを判定する
    ///
    /// ワールド原点のリセット直後は、ごく短い時間に大きな並進・回転が現れる。
    /// このようなフレームは画像と整合しないため破棄する。
    static func isPlausibleMotion(
        translationDelta: Float,
        rotationDelta: Float,
        timeDelta: TimeInterval
    ) -> Bool {
        // 時刻が逆行・停止しているフレームは判定できないため不連続扱い
        guard timeDelta > 0 else { return false }

        let elapsed = Float(timeDelta)
        let translationLimit = maxTranslationSpeed * elapsed + motionToleranceTranslation
        let rotationLimit = maxRotationSpeed * elapsed + motionToleranceRotation
        return translationDelta <= translationLimit && rotationDelta <= rotationLimit
    }

    /// 現在のフレームをキーフレームとして採用すべきかを判定する
    ///
    /// - Parameters:
    ///   - isFirst: セッション内で最初に採用されるフレームか
    ///   - tracking: キャプチャ時のトラッキング品質
    func evaluate(
        translation: SIMD3<Float>,
        quaternion: simd_quatf,
        timestamp: TimeInterval,
        isFirst: Bool,
        tracking: FrameTrackingQuality
    ) -> CaptureDecision {
        let observation = previousObservation
        // 破棄・見送りの場合も次フレームの判定基準になるため必ず更新する
        previousObservation = (translation, quaternion, timestamp)

        // 動きが速すぎる区間はモーションブラーが強く、対応点が取れないため採用しない
        if tracking == .limitedExcessiveMotion { return .skip }

        if isFirst {
            return tracking.isReliable ? .capture : .skip
        }

        // 直前フレームとの姿勢差でワールド原点の飛びを検出する
        if let observation {
            guard Self.isPlausibleMotion(
                translationDelta: simd_length(translation - observation.translation),
                rotationDelta: simd_angle(between: observation.quaternion, and: quaternion),
                timeDelta: timestamp - observation.timestamp
            ) else {
                return .discontinuity
            }
        }

        let timeDelta = timestamp - lastTimestamp
        let translationDelta = simd_length(translation - lastTranslation)
        let rotationDelta = simd_angle(between: lastQuaternion, and: quaternion)

        if timeDelta >= maxFrameInterval { return .capture }
        if translationDelta >= minTranslationDistance { return .capture }
        if rotationDelta >= minRotationAngle { return .capture }
        return .skip
    }

    /// 現在のフレームをキーフレームとして選択すべきかを判定する
    func shouldCapture(
        translation: SIMD3<Float>,
        quaternion: simd_quatf,
        timestamp: TimeInterval,
        isFirst: Bool
    ) -> Bool {
        if isFirst { return true }

        let timeDelta = timestamp - lastTimestamp
        if timeDelta >= maxFrameInterval { return true }

        let translationDelta = simd_length(translation - lastTranslation)
        if translationDelta >= minTranslationDistance { return true }

        let rotationDelta = simd_angle(between: lastQuaternion, and: quaternion)
        if rotationDelta >= minRotationAngle { return true }

        return false
    }

    /// 最後にキャプチャしたフレーム情報を更新する
    func updateLast(translation: SIMD3<Float>, quaternion: simd_quatf, timestamp: TimeInterval) {
        lastTranslation = translation
        lastQuaternion = quaternion
        lastTimestamp = timestamp
        previousObservation = (translation, quaternion, timestamp)
    }

    func reset() {
        lastTranslation = .zero
        lastQuaternion = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        lastTimestamp = 0
        previousObservation = nil
    }

    // MARK: - Private Helpers

    #if canImport(UIKit)
    /// `_depth.bin` の内容から可視化用の UIImage を生成する
    ///
    /// 深度マップもカラー画像と同じセンサ基準（ランドスケープ）のため、
    /// ポートレート表示に合わせて `.right` の向きを付与する。
    static func depthPreviewImage(
        from data: Data,
        orientation: UIImage.Orientation = captureImageOrientation
    ) -> UIImage? {
        guard let map = decodeDepthBinary(data) else { return nil }
        var pixels = depthRGBAPixels(from: map)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        return pixels.withUnsafeMutableBytes { rawBuffer -> UIImage? in
            guard let context = CGContext(
                data: rawBuffer.baseAddress,
                width: map.width,
                height: map.height,
                bitsPerComponent: 8,
                bytesPerRow: map.width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ), let cgImage = context.makeImage() else { return nil }
            return UIImage(cgImage: cgImage, scale: 1, orientation: orientation)
        }
    }

    /// JPEG データをセンサ基準の RGBA ピクセル列へデコードする
    ///
    /// EXIF の向きは適用せず、常に保存時のピクセル配置（センサ基準）で取り出す。
    /// 点群生成では深度マップと同じ向きで扱う必要があるため。
    static func decodeSensorOrientedRGBA(jpeg data: Data) -> ColorImage? {
        guard let cgImage = UIImage(data: data)?.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return nil }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let success = pixels.withUnsafeMutableBytes { rawBuffer -> Bool in
            guard let context = CGContext(
                data: rawBuffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard success else { return nil }
        return ColorImage(width: width, height: height, rgba: pixels)
    }

    private static func createGrayscalePNG(pixels: [UInt8], width: Int, height: Int) -> Data? {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        var pixelsCopy = pixels
        return pixelsCopy.withUnsafeMutableBytes { rawBuffer -> Data? in
            guard let context = CGContext(
                data: rawBuffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ), let cgImage = context.makeImage() else { return nil }

            return UIImage(cgImage: cgImage).pngData()
        }
    }
    #endif
}

// MARK: - simd_quatf helpers

private func simd_angle(between q1: simd_quatf, and q2: simd_quatf) -> Float {
    // クォータニオン間の角度差
    let dot = abs(q1.vector.x * q2.vector.x +
                  q1.vector.y * q2.vector.y +
                  q1.vector.z * q2.vector.z +
                  q1.vector.w * q2.vector.w)
    return 2.0 * acos(min(dot, 1.0))
}
