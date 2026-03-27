#if canImport(SwiftUI)
import SwiftUI

/// スキャン確認・詳細画面
struct SessionDetailView: View {

    let session: ScanSession
    @ObservedObject var viewModel: HistoryViewModel

    @State private var frames: [PoseFrame] = []
    @State private var isLoadingFrames: Bool = true

    private let columns = [GridItem(.adaptive(minimum: 100, maximum: 150), spacing: 4)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                metadataSection
                trajectorySection
                framesSection
            }
            .padding()
        }
        .navigationTitle(session.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    viewModel.shareSession(session)
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
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
            Text("フレーム (\(frames.count))")
                .font(.headline)

            if isLoadingFrames {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(frames.prefix(50)) { frame in
                        FrameThumbnailView(
                            imageURL: viewModel.colorImageURL(
                                index: frame.index,
                                sessionID: session.id
                            )
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

// MARK: - FrameThumbnailView

struct FrameThumbnailView: View {
    let imageURL: URL

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
                        Image(systemName: "photo")
                            .foregroundColor(.secondary)
                    }
            }
        }
        .frame(width: 100, height: 75)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .onAppear { loadImage() }
    }

    private func loadImage() {
        Task.detached(priority: .utility) {
            guard let data = try? Data(contentsOf: imageURL),
                  let uiImage = UIImage(data: data) else { return }
            await MainActor.run { image = uiImage }
        }
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
