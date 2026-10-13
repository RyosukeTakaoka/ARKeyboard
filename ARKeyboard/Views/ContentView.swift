import SwiftUI

/// アプリのメイン画面。カメラ映像の上に、各種の表示を重ねていきます。
///
/// 重ね順(下から上):
///   カメラ映像 → キー配置 → 手の骨格 → 入力テキスト・操作バー・案内
struct ContentView: View {
    /// ViewModel は画面と同じだけ生きていてほしいので @State で持ちます(iOS 17 の @Observable 流儀)。
    @State private var viewModel = KeyboardViewModel()
    @State private var isShowingSettings = false

    /// アプリが前面にあるか、バックグラウンドにあるか
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            switch viewModel.cameraStatus {
            case .running:
                runningView
            default:
                CameraStatusView(status: viewModel.cameraStatus)
            }
        }
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
        // バックグラウンドに入ったらカメラを止め、戻ったら再開します(電池の節約)。
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active: viewModel.start()
            case .background: viewModel.stop()
            default: break
            }
        }
        // 設定が変わったら保存する
        .onChange(of: viewModel.settings) { _, _ in
            viewModel.saveSettings()
            // マイク・加速度センサーのオン/オフや設定を反映する
            viewModel.applySensorSettings()
        }
        // 手の追跡器の切り替え
        .onChange(of: viewModel.settings.handTracker) { _, _ in
            viewModel.applyTracker()
        }
        // LiDAR のオン/オフでカメラを切り替える
        .onChange(of: viewModel.settings.useLiDAR) { _, _ in
            viewModel.applyCameraSource()
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(viewModel: viewModel)
                // 半分の高さでも開けるようにして、カメラ映像を見ながら調整できるようにする
                .presentationDetents([.medium, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
    }

    /// カメラが動いているときの画面
    private var runningView: some View {
        ZStack {
            if viewModel.isUsingDepthCamera, let depthCamera = viewModel.depthCamera {
                ARPreviewView(session: depthCamera.session)
                    .ignoresSafeArea()
            } else {
                CameraPreviewView(session: viewModel.camera.session)
                    .ignoresSafeArea()
            }

            // カメラ映像の上に重ねる表示。プレビューと「同じ大きさ・同じ位置」に置くことが大切です
            // (そうしないと、画像座標→画面座標の変換がずれます)。
            GeometryReader { geometry in
                let converter = CoordinateConverter(imageSize: viewModel.imageSize,
                                                    viewSize: Vec2(geometry.size))
                let projection = LayoutProjection(converter: converter, planeToImage: viewModel.planeToImage)
                ZStack {
                    if viewModel.settings.mode == .desk, let plane = viewModel.deskPlane {
                        DeskPlaneOutlineView(plane: plane, converter: converter)
                    }
                    if viewModel.settings.overlayMode == .hitMap {
                        HitMapOverlayView(hitMaps: viewModel.hitMaps,
                                          keys: viewModel.keys,
                                          frames: viewModel.layoutFrames,
                                          projection: projection)
                    }
                    if viewModel.settings.overlayMode == .heatmap {
                        HeatmapOverlayView(points: viewModel.heatmapPoints,
                                           frames: viewModel.layoutFrames,
                                           projection: projection)
                    }
                    KeyboardOverlayView(keys: viewModel.keys,
                                        frames: viewModel.layoutFrames,
                                        hoveredKeyIDs: viewModel.hoveredKeyIDs,
                                        pressedKeys: viewModel.pressedKeys,
                                        projection: projection)
                    HandSkeletonView(hands: viewModel.hands,
                                     frames: viewModel.layoutFrames,
                                     converter: converter,
                                     minConfidence: viewModel.settings.minConfidence,
                                     planeToImage: viewModel.planeToImage)
                    if viewModel.isRegisteringDesk {
                        DeskRegistrationView(viewModel: viewModel, converter: converter)
                    }
                }
            }
            .ignoresSafeArea()

            VStack(spacing: 8) {
                TextDisplayView(text: viewModel.typedText,
                                onBackspace: { viewModel.backspace() },
                                onNewline: { viewModel.newline() },
                                onClear: { viewModel.clearText() })

                if viewModel.calibration == nil && !viewModel.isCalibrating {
                    hintBanner("まず下の「キャリブレーション」を押して、両手をホームポジションに置いてください")
                }

                if viewModel.isRecording {
                    RecordingView(viewModel: viewModel)
                }

                if let practice = viewModel.practice {
                    PracticeView(session: practice,
                                 now: { viewModel.now },
                                 onNext: { viewModel.nextPracticeSentence() },
                                 onStop: { viewModel.stopPractice() })
                }

                if viewModel.settings.showDebug {
                    DebugOverlayView(viewModel: viewModel)
                }

                Spacer()

                if viewModel.isCalibrating {
                    CalibrationOverlayView(phase: viewModel.calibrationPhase,
                                           message: viewModel.calibrationMessage,
                                           onCancel: { viewModel.cancelCalibration() })
                }

                ControlBarView(viewModel: viewModel, onOpenSettings: { isShowingSettings = true })
            }
        }
    }

    private func hintBanner(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .padding(10)
            .background(.yellow.opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
            .foregroundStyle(.black)
            .padding(.horizontal)
    }
}

#Preview {
    ContentView()
}
