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
                CameraPreviewView(session: viewModel.camera.session)
                    .ignoresSafeArea()
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
}

#Preview {
    ContentView()
}
