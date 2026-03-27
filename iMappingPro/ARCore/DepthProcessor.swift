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
    static func depthToBinary(pixelBuffer: CVPixelBuffer) -> Data? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }

        var data = Data()
        // ヘッダ: width, height (UInt32)
        var w = UInt32(width)
        var h = UInt32(height)
        data.append(contentsOf: withUnsafeBytes(of: &w) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: &h) { Array($0) })

        // 深度値 (Float32)
        let byteCount = width * height * MemoryLayout<Float32>.size
        let depthData = Data(bytes: baseAddress, count: byteCount)
        data.append(depthData)

        return data
    }

    /// 信頼度マップを PNG 用 Data に変換する（UInt8 グレースケール）
    static func confidenceToData(pixelBuffer: CVPixelBuffer) -> Data? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }

        // UInt8 の各値をグレースケール値にマッピング（0=0, 1=127, 2=254）
        let ptr = baseAddress.assumingMemoryBound(to: UInt8.self)
        var pixels = [UInt8](repeating: 0, count: width * height)
        for i in 0..<(width * height) {
            let level = min(Int(ptr[i]), 2)
            pixels[i] = UInt8(level * 127)
        }

        // CGImage 経由で PNG Data を作成
        return createGrayscalePNG(pixels: pixels, width: width, height: height)
    }

    /// RGB フレームを JPEG Data に変換する（YCbCr → UIImage 経由）
    static func colorToJPEGData(pixelBuffer: CVPixelBuffer, quality: CGFloat = 0.9) -> Data? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        let uiImage = UIImage(cgImage: cgImage)
        return uiImage.jpegData(compressionQuality: quality)
    }
    #endif

    // MARK: - Key Frame Selection

    private var lastTranslation: SIMD3<Float> = .zero
    private var lastQuaternion: simd_quatf = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
    private var lastTimestamp: TimeInterval = 0

    let minTranslationDistance: Float = 0.05  // 5cm
    let minRotationAngle: Float = 0.05        // ~3°
    let maxFrameInterval: TimeInterval = 1.0  // 最大1秒

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
    }

    func reset() {
        lastTranslation = .zero
        lastQuaternion = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        lastTimestamp = 0
    }

    // MARK: - Private Helpers

    #if canImport(UIKit)
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
