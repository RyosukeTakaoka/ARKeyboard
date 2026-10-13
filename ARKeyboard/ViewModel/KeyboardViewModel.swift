import Foundation
import Observation

/// 画面(View)とロジックをつなぐクラス。
///
/// `@Observable`(iOS 17〜)を付けると、このクラスのプロパティが変わったときに、
/// それを表示している View だけが自動で再描画されます。
///
/// このクラスのメソッドとプロパティは、すべて**メインスレッド**から使います。
/// (カメラ側が結果をメインスレッドに渡してくれるので、ここでスレッドを気にする必要はありません)
///
/// 役割分担:
/// - 計算(左右の割り当て・座標系・キャリブレーション・タップ判定)は KeyboardEngine(Core)
/// - このクラスは「カメラ → エンジン → 画面」の受け渡しと、触覚・音などの iPhone 固有の処理
@Observable
final class KeyboardViewModel {
    // MARK: 画面に表示する状態

    /// カメラの状態(画面の出し分けに使う)
    var cameraStatus: CameraStatus = .idle
    /// 向き補正後の画像サイズ(ピクセル)。画面座標への変換に使う。
    var imageSize = Vec2(720, 1280)
    /// 最新フレームで検出された手(左右を割り当て済み)
    var hands: [Chirality: HandObservation] = [:]
    /// キー配置の基準にしている手の座標系
    var layoutFrames: [Chirality: HandFrame] = [:]
    /// キャリブレーションの進み具合と案内
    var calibrationPhase: Calibrator.Phase = .idle
    var calibrationMessage = ""
    /// キャリブレーション結果
    var calibration: CalibrationResult?
    /// 手ごとのキー(手の座標)
    var keys: [Chirality: [Key]] = [:]
    /// 指先の下にあるキー
    var hoveredKeyIDs: Set<String> = []
    /// 押されたキーと押された時刻(押した瞬間にキーを光らせる)
    var pressedKeys: [String: Date] = [:]

    // MARK: 内部で使うもの(View から監視する必要がないので @ObservationIgnored)

    /// カメラ
    @ObservationIgnored let camera = CameraManager()
    /// 計算を担当するエンジン
    @ObservationIgnored private let engine = KeyboardEngine()

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

    // MARK: キャリブレーション

    /// キャリブレーション中か。
    /// (engine は監視対象外なので、監視対象の calibrationPhase から求める。
    ///  こうしないと、値が変わっても画面が更新されません)
    var isCalibrating: Bool {
        switch calibrationPhase {
        case .waitingForHands, .holding: return true
        case .idle, .finished: return false
        }
    }

    func startCalibration() {
        engine.startCalibration()
        syncCalibrationState()
    }

    func cancelCalibration() {
        engine.calibrator.cancel()
        syncCalibrationState()
    }

    // MARK: フレーム処理

    /// 1コマ分の認識結果を受け取る(メインスレッド)
    private func handle(_ frame: VisionFrame) {
        imageSize = frame.imageSize
        let output = engine.process(frame)
        hands = output.hands
        layoutFrames = output.layoutFrames
        hoveredKeyIDs = output.hoveredKeyIDs
        syncCalibrationState()
        if let result = output.calibrationFinished {
            calibration = result
            keys = engine.keys
        }
        for tap in output.taps {
            handleTap(tap)
        }
    }

    /// タップ1回分の処理
    private func handleTap(_ tap: TapResult) {
        guard let key = tap.key else { return }
        pressedKeys[key.id] = Date()
    }

    private func syncCalibrationState() {
        calibrationPhase = engine.calibrator.phase
        calibrationMessage = engine.calibrator.message
    }
}
