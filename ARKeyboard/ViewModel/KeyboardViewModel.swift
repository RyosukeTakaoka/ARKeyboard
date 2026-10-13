import Foundation
import Observation
import UIKit
import AudioToolbox

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
/// - このクラスは「カメラ → エンジン → 画面」の受け渡しと、触覚・音・保存などの iPhone 固有の処理
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

    /// 入力された文字列
    var typedText = ""

    /// 設定。画面から直接書き換えてよい(毎フレーム、エンジンに反映されます)。
    /// 保存は ContentView の onChange から saveSettings() を呼んで行います。
    var settings: KeyboardSettings

    // MARK: 内部で使うもの(View から監視する必要がないので @ObservationIgnored)

    /// カメラ
    @ObservationIgnored let camera = CameraManager()
    /// 計算を担当するエンジン
    @ObservationIgnored private let engine: KeyboardEngine
    /// 触覚フィードバック(軽い「コツッ」)
    @ObservationIgnored private let haptics = UIImpactFeedbackGenerator(style: .light)
    /// 完了時の触覚フィードバック(「ブブッ」)
    @ObservationIgnored private let notificationHaptics = UINotificationFeedbackGenerator()

    /// UserDefaults に保存するときのキー(名前)
    private static let settingsKey = "KeyboardSettings.v1"

    init() {
        let loaded = Self.loadSettings()
        settings = loaded
        engine = KeyboardEngine(settings: loaded)

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
        // 触覚フィードバックの準備(最初の1回が遅れないように、あらかじめエンジンを起こしておく)
        haptics.prepare()
        // キーボードとして使っている間は、画面が自動で消えないようにする
        UIApplication.shared.isIdleTimerDisabled = true
    }

    /// 画面が消えたとき・バックグラウンドに入ったときに呼ぶ
    func stop() {
        camera.stop()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    // MARK: 設定

    /// モードを切り替える(モードごとの初期値も当てはめる)
    func setMode(_ mode: KeyboardMode) {
        settings.applyModeDefaults(mode)
    }

    /// 今のモードの初期値に戻す
    func resetToModeDefaults() {
        settings.applyModeDefaults(settings.mode)
    }

    func saveSettings() {
        // Codable なので JSON に変換して保存できる
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Self.settingsKey)
        }
    }

    private static func loadSettings() -> KeyboardSettings {
        guard let data = UserDefaults.standard.data(forKey: settingsKey),
              let settings = try? JSONDecoder().decode(KeyboardSettings.self, from: data) else {
            // 初回起動(または保存形式が変わった)なら、膝モードの初期値から始める
            return KeyboardSettings.defaults(for: .knee)
        }
        return settings
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

    // MARK: テキスト編集(画面のボタンから呼ぶ)

    func insert(_ text: String) {
        typedText += text
    }

    func backspace() {
        guard !typedText.isEmpty else { return }
        typedText.removeLast()
    }

    func newline() {
        insert("\n")
    }

    func clearText() {
        typedText = ""
    }

    // MARK: フレーム処理

    /// 1コマ分の認識結果を受け取る(メインスレッド)
    private func handle(_ frame: VisionFrame) {
        // 画面で変えた設定を、毎フレームエンジンに反映する(struct のコピーなので軽い)
        engine.settings = settings
        // キーの大きさが変わったときなど、キーが作り直されていたら画面にも反映
        if engine.keys != keys {
            keys = engine.keys
        }

        imageSize = frame.imageSize
        let output = engine.process(frame)
        hands = output.hands
        layoutFrames = output.layoutFrames
        hoveredKeyIDs = output.hoveredKeyIDs
        syncCalibrationState()
        if let result = output.calibrationFinished {
            calibration = result
            keys = engine.keys
            notificationHaptics.notificationOccurred(.success)
        }
        for tap in output.taps {
            handleTap(tap)
        }
    }

    /// タップ1回分の処理
    private func handleTap(_ tap: TapResult) {
        guard let key = tap.key else { return }
        pressedKeys[key.id] = Date()
        insert(key.output)

        if settings.hapticsEnabled {
            haptics.impactOccurred()
            haptics.prepare()
        }
        if settings.soundEnabled {
            // 1104 は iOS のキーボードのクリック音(システムサウンド)。
            // 音声ファイルを用意しなくても鳴らせます(消音モードでは鳴りません)。
            AudioServicesPlaySystemSound(1104)
        }
    }

    private func syncCalibrationState() {
        calibrationPhase = engine.calibrator.phase
        calibrationMessage = engine.calibrator.message
    }
}
