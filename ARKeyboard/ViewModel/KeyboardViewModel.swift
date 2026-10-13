import Foundation
import Observation

/// 画面(View)とロジックをつなぐクラス。
///
/// `@Observable`(iOS 17〜)を付けると、このクラスのプロパティが変わったときに、
/// それを表示している View だけが自動で再描画されます。
@Observable
final class KeyboardViewModel {
    /// カメラの状態(画面の出し分けに使う)
    var cameraStatus: CameraStatus = .idle

    /// カメラ。View に「変化を監視」させる必要はないので @ObservationIgnored を付けます。
    @ObservationIgnored let camera = CameraManager()

    /// 画面が表示されたときに呼ぶ
    func start() {
        camera.start { [weak self] status in
            self?.cameraStatus = status
        }
    }

    /// 画面が消えたとき・バックグラウンドに入ったときに呼ぶ
    func stop() {
        camera.stop()
    }
}
