#if canImport(SwiftUI)
import SwiftUI

/// スキャン確認・詳細画面
struct SessionDetailView: View {

    let session: ScanSession
    @ObservedObject var viewModel: HistoryViewModel

    @State private var frames: [PoseFrame] = []
    @State private var isLoadingFrames: Bool = true
    @State private var previewMode: FramePreviewMode = .color
    @State private var geometryMode: GeometryPreviewMode = .mesh

    private let columns = [GridItem(.adaptive(minimum: 100, maximum: 150), spacing: 4)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                metadataSection
                meshSection
                trajectorySection
                framesSection
            }
            .padding()
        }
        .navigationTitle(session.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        viewModel.shareSession(session, target: .archive)
                    } label: {
                        Label("セッション一式 (ZIP)", systemImage: "doc.zipper")
                    }
                    Button {
                        viewModel.shareSession(session, target: .mesh)
                    } label: {
                        Label("メッシュ (OBJ)", systemImage: "cube")
                    }
                    .disabled(!hasMesh)
                    Button {
                        viewModel.shareSession(session, target: .pointCloud)
                    } label: {
                        Label("色付き点群 (PLY)", systemImage: "aqi.medium")
                    }
                    .disabled(!hasPointCloud)
                    Button {
                        viewModel.shareSession(session, target: .poses)
                    } label: {
                        Label("姿勢データ (poses.json)", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                    }
                } label: {
                    if viewModel.isPreparingArchive {
                        ProgressView()
                    } else {
                        Image(systemName: "square.and.arrow.down")
                    }
                }
                .disabled(viewModel.isPreparingArchive)
            }
        }
        .onAppear {
            loadFrames()
        }
        .sheet(item: $viewModel.sharingURL) { url in
            ShareSheet(items: [url])
        }
    }

    // MARK: - Metadata Section

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("セッション情報")
                .font(.headline)

            Grid(alignment: .leading, verticalSpacing: 8) {
                metadataRow(label: "作成日時", value: session.formattedDate, icon: "calendar")
                metadataRow(label: "フレーム数", value: "\(session.frameCount) フレーム", icon: "camera")
                metadataRow(label: "スキャン時間", value: session.formattedDuration, icon: "clock")
                metadataRow(label: "推定容量", value: String(format: "%.0f MB", session.estimatedFileSizeMB), icon: "internaldrive")
                metadataRow(label: "メッシュ", value: session.formattedMeshSummary, icon: "cube")
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func metadataRow(label: String, value: String, icon: String) -> some View {
        GridRow {
            Label(label, systemImage: icon)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .gridColumnAlignment(.leading)
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .gridColumnAlignment(.leading)
        }
    }

    // MARK: - Mesh Section

    private var meshSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("3D プレビュー")
                .font(.headline)

            if hasPointCloud && hasMesh {
                Picker("表示種別", selection: $geometryMode) {
                    ForEach(GeometryPreviewMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            if let source = geometrySource {
                MeshPreviewView(source: source)
                    .frame(height: 260)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

                Text(source.isPointCloud
                     ? "RGB フレームと深度から生成した色付き点群です。ドラッグで回転、ピンチで拡大縮小できます。"
                     : "ドラッグで回転、ピンチで拡大縮小できます。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "cube.transparent")
                        .font(.title)
                        .foregroundColor(.secondary)
                    Text("メッシュデータがありません")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 140)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    /// 表示可能なジオメトリ（選択中のモードが無い場合はもう一方にフォールバック）
    private var geometrySource: ScenePreviewSource? {
        switch geometryMode {
        case .mesh:
            if hasMesh { return .mesh(viewModel.meshURL(for: session)) }
            if hasPointCloud { return .pointCloud(viewModel.pointCloudURL(for: session)) }
        case .pointCloud:
            if hasPointCloud { return .pointCloud(viewModel.pointCloudURL(for: session)) }
            if hasMesh { return .mesh(viewModel.meshURL(for: session)) }
        }
        return nil
    }

    private var hasMesh: Bool {
        session.hasMesh || viewModel.hasMesh(session)
    }

    private var hasPointCloud: Bool {
        viewModel.hasPointCloud(session)
    }

    // MARK: - Trajectory Section

    private var trajectorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("軌跡 (XZ 平面)")
                .font(.headline)

            if frames.isEmpty {
                Text("軌跡データがありません")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
            } else {
                TrajectoryView(frames: frames)
                    .frame(height: 200)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Frames Section

    private var framesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("フレーム (\(frames.count))")
                    .font(.headline)
                Spacer()
            }

            Picker("プレビュー種別", selection: $previewMode) {
                ForEach(FramePreviewMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if isLoadingFrames {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(frames.prefix(50)) { frame in
                        FrameThumbnailView(
                            imageURL: previewMode == .color
                                ? viewModel.colorImageURL(index: frame.index, sessionID: session.id)
                                : viewModel.depthMapURL(index: frame.index, sessionID: session.id),
                            mode: previewMode
                        )
                    }
                }

                if frames.count > 50 {
                    Text("...他 \(frames.count - 50) フレーム")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Load

    private func loadFrames() {
        isLoadingFrames = true
        Task {
            frames = viewModel.loadFrames(for: session)
            isLoadingFrames = false
        }
    }
}

// MARK: - TrajectoryView

struct TrajectoryView: View {
    let frames: [PoseFrame]

    var body: some View {
        Canvas { context, size in
            guard frames.count > 1 else { return }

            let xs = frames.map { $0.translationX }
            let zs = frames.map { $0.translationZ }

            guard let minX = xs.min(), let maxX = xs.max(),
                  let minZ = zs.min(), let maxZ = zs.max() else { return }

            let rangeX = max(maxX - minX, 0.1)
            let rangeZ = max(maxZ - minZ, 0.1)
            let padding: Double = 20

            func point(tx: Float, tz: Float) -> CGPoint {
                let nx = (Double(tx - minX) / Double(rangeX)) * (size.width - 2 * padding) + padding
                let ny = (Double(tz - minZ) / Double(rangeZ)) * (size.height - 2 * padding) + padding
                return CGPoint(x: nx, y: ny)
            }

            var path = Path()
            path.move(to: point(tx: frames[0].translationX, tz: frames[0].translationZ))
            for frame in frames.dropFirst() {
                path.addLine(to: point(tx: frame.translationX, tz: frame.translationZ))
            }
            context.stroke(path, with: .color(.blue), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

            // 開始点 (緑)
            if let first = frames.first {
                let start = point(tx: first.translationX, tz: first.translationZ)
                context.fill(Path(ellipseIn: CGRect(x: start.x - 5, y: start.y - 5, width: 10, height: 10)), with: .color(.green))
            }

            // 終了点 (赤)
            if let last = frames.last {
                let end = point(tx: last.translationX, tz: last.translationZ)
                context.fill(Path(ellipseIn: CGRect(x: end.x - 5, y: end.y - 5, width: 10, height: 10)), with: .color(.red))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - GeometryPreviewMode

/// 3D プレビューの表示種別
enum GeometryPreviewMode: String, CaseIterable, Identifiable {
    case mesh
    case pointCloud

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mesh: return "メッシュ"
        case .pointCloud: return "色付き点群"
        }
    }
}

// MARK: - FramePreviewMode

/// フレームサムネイルの表示種別
enum FramePreviewMode: String, CaseIterable, Identifiable {
    case color
    case depth

    var id: String { rawValue }

    var title: String {
        switch self {
        case .color: return "RGB"
        case .depth: return "深度"
        }
    }

    var placeholderSymbol: String {
        switch self {
        case .color: return "photo"
        case .depth: return "square.stack.3d.up"
        }
    }
}

// MARK: - FrameThumbnailView

struct FrameThumbnailView: View {
    let imageURL: URL
    var mode: FramePreviewMode = .color

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: mode.placeholderSymbol)
                            .foregroundColor(.secondary)
                    }
            }
        }
        .frame(width: 100, height: 133)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .task(id: imageURL) { await loadImage() }
    }

    private func loadImage() async {
        let url = imageURL
        let mode = mode
        let loaded = await Task.detached(priority: .utility) { () -> UIImage? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            switch mode {
            case .color:
                return UIImage(data: data)
            case .depth:
                return DepthProcessor.depthPreviewImage(from: data)
            }
        }.value
        image = loaded
    }
}

#Preview {
    NavigationStack {
        SessionDetailView(
            session: ScanSession(name: "テストスキャン", frameCount: 10, durationSeconds: 5),
            viewModel: HistoryViewModel()
        )
    }
}

#endif // canImport(SwiftUI)
