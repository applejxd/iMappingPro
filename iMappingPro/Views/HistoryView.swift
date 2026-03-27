import SwiftUI

/// スキャン履歴一覧画面
struct HistoryView: View {

    @StateObject private var viewModel = HistoryViewModel()
    @State private var showingRenameAlert: Bool = false
    @State private var renamingSession: ScanSession?
    @State private var renameText: String = ""
    @State private var showingDeleteAlert: Bool = false
    @State private var deletingSession: ScanSession?
    @State private var showingError: Bool = false
    @State private var sharingItem: URL?

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("読み込み中...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.sessions.isEmpty {
                    emptyState
                } else {
                    sessionList
                }
            }
            .navigationTitle("スキャン履歴")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
            }
        }
        .onAppear {
            viewModel.loadSessions()
        }
        .alert("名前を変更", isPresented: $showingRenameAlert) {
            TextField("セッション名", text: $renameText)
            Button("変更") {
                if let session = renamingSession {
                    viewModel.renameSession(session, to: renameText)
                }
                renamingSession = nil
                renameText = ""
            }
            Button("キャンセル", role: .cancel) {
                renamingSession = nil
                renameText = ""
            }
        }
        .alert("削除の確認", isPresented: $showingDeleteAlert) {
            Button("削除", role: .destructive) {
                if let session = deletingSession {
                    viewModel.deleteSession(session)
                }
                deletingSession = nil
            }
            Button("キャンセル", role: .cancel) {
                deletingSession = nil
            }
        } message: {
            Text("「\(deletingSession?.name ?? "")」を削除します。この操作は元に戻せません。")
        }
        .alert("エラー", isPresented: $showingError) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .onChange(of: viewModel.errorMessage) { newValue in
            showingError = newValue != nil
        }
        .sheet(item: $sharingItem) { url in
            ShareSheet(items: [url])
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "scanner")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text("スキャン履歴がありません")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("スキャンタブからスキャンを開始し、保存してください。")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Session List

    private var sessionList: some View {
        List {
            ForEach(viewModel.sessions) { session in
                NavigationLink(destination: SessionDetailView(session: session, viewModel: viewModel)) {
                    SessionRowView(session: session)
                }
                .contextMenu {
                    Button {
                        renamingSession = session
                        renameText = session.name
                        showingRenameAlert = true
                    } label: {
                        Label("リネーム", systemImage: "pencil")
                    }

                    Button {
                        viewModel.shareSession(session)
                    } label: {
                        Label("共有", systemImage: "square.and.arrow.up")
                    }

                    Divider()

                    Button(role: .destructive) {
                        deletingSession = session
                        showingDeleteAlert = true
                    } label: {
                        Label("削除", systemImage: "trash")
                    }
                }
            }
            .onDelete { indexSet in
                viewModel.deleteSessions(at: indexSet)
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            viewModel.loadSessions()
        }
        .onChange(of: viewModel.sharingURL) { newValue in
            sharingItem = newValue
        }
    }
}

// MARK: - SessionRowView

struct SessionRowView: View {
    let session: ScanSession

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.name)
                .font(.headline)
                .lineLimit(1)

            HStack(spacing: 12) {
                Label("\(session.frameCount) frames", systemImage: "camera")
                Label(session.formattedDuration, systemImage: "clock")
                Label(String(format: "%.0f MB", session.estimatedFileSizeMB), systemImage: "internaldrive")
            }
            .font(.caption)
            .foregroundColor(.secondary)

            Text(session.formattedDate)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - URL Identifiable

extension URL: Identifiable {
    public var id: String { absoluteString }
}

// MARK: - ShareSheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    HistoryView()
}
