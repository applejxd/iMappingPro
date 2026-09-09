#if canImport(SwiftUI)
import SwiftUI

/// メインスキャン画面
struct ScanView: View {

    @StateObject private var viewModel = ScanViewModel()
    @State private var showMesh: Bool = true
    @State private var showingSaveAlert: Bool = false
    @State private var showingResetAlert: Bool = false
    @State private var sessionName: String = ""
    @State private var showingError: Bool = false

    var body: some View {
        ZStack {
            // AR プレビュー（フルスクリーン）
            ARContainerView(
                arSession: viewModel.sessionManager.arSession,
                showMesh: showMesh && viewModel.isMeshPreviewAvailable,
                showCoaching: viewModel.isCoachingActive,
                originTransform: viewModel.displayedOriginTransform
            )
            .ignoresSafeArea()

            // オーバーレイ
            VStack {
                statusOverlay
                Spacer()
                controlPanel
            }

            if let countdown = viewModel.countdown {
                countdownOverlay(countdown)
            }
        }
        .onAppear {
            viewModel.prepareSession()
        }
        .alert("スキャンを保存", isPresented: $showingSaveAlert) {
            TextField("スキャン名", text: $sessionName)
            Button("保存") {
                viewModel.saveSession(name: sessionName)
                sessionName = ""
            }
            Button("キャンセル", role: .cancel) {
                sessionName = ""
                viewModel.cancelSavePrompt()
            }
        } message: {
            Text("このスキャンに名前を付けて保存します。")
        }
        .alert("スキャンをリセット", isPresented: $showingResetAlert) {
            Button("リセット", role: .destructive) {
                viewModel.resetScanning()
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("現在のスキャンデータをすべて破棄します。よろしいですか？")
        }
        .alert("エラー", isPresented: $showingError) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "不明なエラーが発生しました。")
        }
        .onChange(of: viewModel.errorMessage) { newValue in
            showingError = newValue != nil
        }
        .overlay {
            if viewModel.isSaving {
                savingOverlay
            }
        }
    }

    // MARK: - Status Overlay

    private var statusOverlay: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                // トラッキング状態
                HStack(spacing: 6) {
                    Circle()
                        .fill(trackingColor)
                        .frame(width: 10, height: 10)
                    Text(viewModel.trackingState.displayText)
                        .font(.caption)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())

                Spacer()

                // フレーム数・距離・時間
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(viewModel.frameCount) frames")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.white)
                    Text(String(format: "%.2f m", viewModel.totalDistance))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.white)
                    Text(formattedElapsed)
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.white)
                    if viewModel.missingDepthCount > 0 {
                        Text("深度欠落 \(viewModel.missingDepthCount)")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.yellow)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }

            if let notice = viewModel.notice {
                Label(notice, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.notice)
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    // MARK: - Countdown Overlay

    /// 開始前カウントダウン
    ///
    /// ARKit のトラッキングが収束するまでの時間を稼ぐと同時に、
    /// 「いつ記録が始まるか」をユーザに伝える。
    private func countdownOverlay(_ value: Int) -> some View {
        VStack(spacing: 12) {
            Text("\(value)")
                .font(.system(size: 96, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundColor(.white)
                .contentTransition(.numericText())
            Text("端末をゆっくり動かして構えてください")
                .font(.subheadline)
                .foregroundColor(.white)
        }
        .padding(32)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: value)
    }

    // MARK: - Control Panel

    private var controlPanel: some View {
        VStack(spacing: 12) {
            // メッシュ表示切り替え
            Toggle("LiDAR メッシュ", isOn: $showMesh)
                .toggleStyle(.button)
                .tint(.blue)
                .font(.caption)

            // メインコントロール
            HStack(spacing: 12) {
                // Start / Stop / Resume
                Button(action: primaryAction) {
                    controlLabel(primaryButtonTitle, systemImage: primaryButtonIcon)
                }
                .buttonStyle(.borderedProminent)
                .tint(primaryButtonColor)
                .disabled(viewModel.scanState == .saving)

                // Save
                Button {
                    sessionName = "スキャン \(formattedDate)"
                    // 名前の入力中に姿勢が不連続と判定されないようキャプチャを止める
                    viewModel.beginSavePrompt()
                    showingSaveAlert = true
                } label: {
                    controlLabel("保存", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(viewModel.frameCount == 0 || viewModel.scanState == .saving)

                // Reset
                Button {
                    showingResetAlert = true
                } label: {
                    controlLabel("リセット", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(viewModel.scanState == .idle
                          || viewModel.scanState == .preparing
                          || viewModel.scanState == .saving)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    // MARK: - Saving Overlay

    private var savingOverlay: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
                Text("保存中...")
                    .foregroundColor(.white)
                    .font(.headline)
            }
            .padding(32)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: - Helpers

    /// 操作ボタンのラベル
    ///
    /// 3 ボタンを横並びにすると 1 つあたりの幅が狭く、「リセット」のような
    /// 4 文字のラベルが折り返されるため、1 行に固定して必要な分だけ縮小する。
    private func controlLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity)
    }

    private var trackingColor: Color {
        switch viewModel.trackingState {
        case .normal:       return .green
        case .limited:      return .yellow
        case .notAvailable: return .red
        }
    }

    private var primaryButtonTitle: String {
        switch viewModel.scanState {
        case .idle:      return "開始"
        case .preparing: return "中止"
        case .scanning:  return "停止"
        case .paused:    return "再開"
        case .saving:    return "保存中"
        }
    }

    private var primaryButtonIcon: String {
        switch viewModel.scanState {
        case .idle:      return "record.circle"
        case .preparing: return "xmark.circle"
        case .scanning:  return "pause.circle"
        case .paused:    return "play.circle"
        case .saving:    return "hourglass"
        }
    }

    private var primaryButtonColor: Color {
        switch viewModel.scanState {
        case .idle:      return .blue
        case .preparing: return .gray
        case .scanning:  return .orange
        case .paused:    return .blue
        case .saving:    return .gray
        }
    }

    private func primaryAction() {
        switch viewModel.scanState {
        case .idle:      viewModel.startScanning()
        case .preparing: viewModel.cancelPreparing()
        case .scanning:  viewModel.stopScanning()
        case .paused:    viewModel.resumeScanning()
        case .saving:    break
        }
    }

    private var formattedElapsed: String {
        let total = Int(viewModel.elapsedSeconds)
        let min = total / 60
        let sec = total % 60
        return String(format: "%02d:%02d", min, sec)
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: Date())
    }
}

#Preview {
    ScanView()
}

#endif // canImport(SwiftUI)
