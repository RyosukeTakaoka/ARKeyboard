import Foundation
import Observation

/// 画面(View)とロジックをつなぐクラス。
///
/// `@Observable`(iOS 17〜)を付けると、このクラスのプロパティが変わったときに、
/// それを表示している View だけが自動で再描画されます。
///
/// このクラスのメソッドとプロパティは、すべて**メインスレッド**から使います。
/// (カメラ側が結果をメインスレッドに渡してくれるので、ここでスレッドを気にする必要はありません)
@Observable
final class KeyboardViewModel {
    // MARK: 画面に表示する状態

    /// カメラの状態(画面の出し分けに使う)
    var cameraStatus: CameraStatus = .idle
    /// 向き補正後の画像サイズ(ピクセル)。画面座標への変換に使う。
    var imageSize = Vec2(720, 1280)
    /// 最新フレームで検出された手
    var hands: [HandObservation] = []

    // MARK: 内部で使うもの(View から監視する必要がないので @ObservationIgnored)

    /// カメラ
    @ObservationIgnored let camera = CameraManager()

    init() {
        // カメラから1コマ届くたびに handle(_:) を呼んでもらう。
        // [weak self] にするのは、ViewModel → camera → クロージャ → ViewModel という
        // 「循環参照」(お互いを離さずメモリが解放されない状態)を防ぐためです。
        camera.onFrame = { [weak self] frame in
            self?.handle(frame)
        }
    }

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

    /// 1コマ分の認識結果を受け取る(メインスレッド)
    private func handle(_ frame: VisionFrame) {
        imageSize = frame.imageSize
        hands = frame.hands
    }
}
