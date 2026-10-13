import SwiftUI

/// アプリのメイン画面。カメラ映像の上に、各種の表示を重ねていきます。
struct ContentView: View {
    /// ViewModel は画面と同じだけ生きていてほしいので @State で持ちます(iOS 17 の @Observable 流儀)。
    @State private var viewModel = KeyboardViewModel()

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
    }

    /// カメラが動いているときの画面
    private var runningView: some View {
        ZStack {
            CameraPreviewView(session: viewModel.camera.session)
                .ignoresSafeArea()

            // カメラ映像の上に重ねる表示。プレビューと「同じ大きさ・同じ位置」に置くことが大切です
            // (そうしないと、画像座標→画面座標の変換がずれます)。
            GeometryReader { geometry in
                let converter = CoordinateConverter(imageSize: viewModel.imageSize,
                                                    viewSize: Vec2(geometry.size))
                ZStack {
                    KeyboardOverlayView(keys: viewModel.keys,
                                        frames: viewModel.layoutFrames,
                                        hoveredKeyIDs: viewModel.hoveredKeyIDs,
                                        pressedKeys: viewModel.pressedKeys,
                                        converter: converter)
                    HandSkeletonView(hands: viewModel.hands,
                                     frames: viewModel.layoutFrames,
                                     converter: converter)
                }
            }
            .ignoresSafeArea()

            VStack {
                Spacer()
                if viewModel.isCalibrating {
                    CalibrationOverlayView(phase: viewModel.calibrationPhase,
                                           message: viewModel.calibrationMessage,
                                           onCancel: { viewModel.cancelCalibration() })
                }
                bottomBar
            }
        }
    }

    /// 画面下の操作ボタン
    private var bottomBar: some View {
        HStack {
            Button {
                viewModel.startCalibration()
            } label: {
                Label(viewModel.calibration == nil ? "キャリブレーション" : "再キャリブレーション",
                      systemImage: "hand.raised")
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isCalibrating)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
