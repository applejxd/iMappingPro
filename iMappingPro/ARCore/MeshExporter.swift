import Foundation
#if canImport(simd)
import simd
#endif
#if canImport(ARKit)
import ARKit
#endif

// MARK: - MeshChunk

/// 1 つの ARMeshAnchor 相当のメッシュ断片（座標はスキャン開始地点を原点とする相対座標系）
struct MeshChunk: Equatable {
    var vertices: [SIMD3<Float>]
    var normals: [SIMD3<Float>]
    /// 三角形の頂点インデックス（vertices 配列に対する 0 始まりの参照）
    var faces: [SIMD3<UInt32>]

    init(vertices: [SIMD3<Float>], normals: [SIMD3<Float>] = [], faces: [SIMD3<UInt32>] = []) {
        self.vertices = vertices
        self.normals = normals
        self.faces = faces
    }

    var isEmpty: Bool { vertices.isEmpty || faces.isEmpty }
}

// MARK: - MeshStatistics

/// メッシュの規模を表すメタ情報
struct MeshStatistics: Equatable {
    let vertexCount: Int
    let faceCount: Int

    var isEmpty: Bool { vertexCount == 0 || faceCount == 0 }
}

// MARK: - MeshExporter

/// 統合メッシュを Wavefront OBJ 形式へ書き出す
enum MeshExporter {

    /// 複数チャンクの合計頂点数・面数を集計する
    static func statistics(of chunks: [MeshChunk]) -> MeshStatistics {
        MeshStatistics(
            vertexCount: chunks.reduce(0) { $0 + $1.vertices.count },
            faceCount: chunks.reduce(0) { $0 + $1.faces.count }
        )
    }

    /// OBJ テキストを生成する
    ///
    /// - 面インデックスはチャンクをまたいでオフセットされ、OBJ 仕様どおり 1 始まりで出力される
    /// - 法線が存在する場合は `f v//vn` 形式、存在しない場合は `f v` 形式になる
    static func objString(chunks: [MeshChunk]) -> String {
        let stats = statistics(of: chunks)

        var lines: [String] = []
        lines.reserveCapacity(stats.vertexCount * 2 + stats.faceCount + 4)
        lines.append("# iMappingPro mesh export")
        lines.append("# vertices: \(stats.vertexCount)")
        lines.append("# faces: \(stats.faceCount)")
        lines.append("o iMappingProMesh")

        var vertexOffset: UInt32 = 0
        for chunk in chunks {
            for vertex in chunk.vertices {
                lines.append("v \(format(vertex.x)) \(format(vertex.y)) \(format(vertex.z))")
            }
            for normal in chunk.normals {
                lines.append("vn \(format(normal.x)) \(format(normal.y)) \(format(normal.z))")
            }

            let hasNormals = chunk.normals.count == chunk.vertices.count
            for face in chunk.faces {
                let i0 = face.x + vertexOffset + 1
                let i1 = face.y + vertexOffset + 1
                let i2 = face.z + vertexOffset + 1
                if hasNormals {
                    lines.append("f \(i0)//\(i0) \(i1)//\(i1) \(i2)//\(i2)")
                } else {
                    lines.append("f \(i0) \(i1) \(i2)")
                }
            }
            vertexOffset += UInt32(chunk.vertices.count)
        }

        return lines.joined(separator: "\n") + "\n"
    }

    /// OBJ テキストを UTF-8 Data として生成する
    static func objData(chunks: [MeshChunk]) -> Data? {
        objString(chunks: chunks).data(using: .utf8)
    }

    // MARK: - Private

    private static func format(_ value: Float) -> String {
        String(format: "%.4f", value)
    }
}

// MARK: - ARKit Extraction

#if canImport(ARKit)

extension MeshExporter {

    /// ARMeshAnchor のジオメトリを相対座標系のメッシュ断片へ変換する
    ///
    /// - Parameters:
    ///   - anchor: ARKit のシーン再構成メッシュアンカー
    ///   - referenceTransform: スキャン開始地点のカメラ姿勢（この逆行列で相対座標系へ揃える）
    @available(iOS 13.4, *)
    static func chunk(from anchor: ARMeshAnchor, referenceTransform: simd_float4x4) -> MeshChunk? {
        let geometry = anchor.geometry
        let vertexSource = geometry.vertices
        let normalSource = geometry.normals
        let faceElement = geometry.faces

        guard vertexSource.format == .float3,
              faceElement.indexCountPerPrimitive == 3,
              faceElement.bytesPerIndex == MemoryLayout<UInt32>.size else {
            return nil
        }

        // アンカーはワールド座標系に置かれているため、初期姿勢基準の相対座標系へ変換する
        let toRelative = simd_inverse(referenceTransform) * anchor.transform
        let rotation = simd_float3x3(
            SIMD3<Float>(toRelative.columns.0.x, toRelative.columns.0.y, toRelative.columns.0.z),
            SIMD3<Float>(toRelative.columns.1.x, toRelative.columns.1.y, toRelative.columns.1.z),
            SIMD3<Float>(toRelative.columns.2.x, toRelative.columns.2.y, toRelative.columns.2.z)
        )

        var vertices: [SIMD3<Float>] = []
        vertices.reserveCapacity(vertexSource.count)
        let vertexBase = vertexSource.buffer.contents()
        for i in 0..<vertexSource.count {
            let pointer = vertexBase.advanced(by: vertexSource.offset + vertexSource.stride * i)
            let local = pointer.assumingMemoryBound(to: (Float, Float, Float).self).pointee
            let transformed = toRelative * SIMD4<Float>(local.0, local.1, local.2, 1)
            vertices.append(SIMD3<Float>(transformed.x, transformed.y, transformed.z))
        }

        var normals: [SIMD3<Float>] = []
        if normalSource.format == .float3, normalSource.count == vertexSource.count {
            normals.reserveCapacity(normalSource.count)
            let normalBase = normalSource.buffer.contents()
            for i in 0..<normalSource.count {
                let pointer = normalBase.advanced(by: normalSource.offset + normalSource.stride * i)
                let local = pointer.assumingMemoryBound(to: (Float, Float, Float).self).pointee
                let rotated = rotation * SIMD3<Float>(local.0, local.1, local.2)
                let length = simd_length(rotated)
                normals.append(length > 0 ? rotated / length : rotated)
            }
        }

        var faces: [SIMD3<UInt32>] = []
        faces.reserveCapacity(faceElement.count)
        let faceBase = faceElement.buffer.contents()
        let strideBytes = faceElement.indexCountPerPrimitive * faceElement.bytesPerIndex
        for i in 0..<faceElement.count {
            let pointer = faceBase.advanced(by: i * strideBytes).assumingMemoryBound(to: UInt32.self)
            faces.append(SIMD3<UInt32>(pointer[0], pointer[1], pointer[2]))
        }

        let chunk = MeshChunk(vertices: vertices, normals: normals, faces: faces)
        return chunk.isEmpty ? nil : chunk
    }
}

#endif // canImport(ARKit)
