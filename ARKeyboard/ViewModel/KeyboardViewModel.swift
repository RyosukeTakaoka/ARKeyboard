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
    /// 当たり判定の地図(当たり判定ビューを表示しているときだけ計算する)
    var hitMaps: [Chirality: HitMap] = [:]

    /// 入力された文字列
    var typedText = ""
    /// 記録モード中か(記録モードは RecordingSession で実装)
    var isRecording = false
    /// 練習モード(nil なら練習していない)
    var practice: PracticeSession?

    // MARK: デバッグ表示用

    /// 1秒あたりの処理コマ数
    var fps: Double = 0
    /// Vision が検出した手の数(左右の割り当て前)
    var detectedHandCount = 0
    /// 速度グラフ用の、選んだ指の直近の値
    var signalHistory: [FingerSignalSample] = []
    /// 直近のタップの記録(新しい順)
    var tapLog: [TapLogEntry] = []
    /// 音の特徴の直近の記録(デバッグの波形表示用)
    var audioHistory: [AudioFeature] = []
    /// 直近の音のオンセット(デバッグ表示用)
    var recentOnsets: [OnsetEvent] = []
    /// 直近のカメラのタップ候補の時刻(音の波形と並べて表示する)
    var recentVisionTapTimes: [Double] = []
    /// マイク・加速度センサーの状態(表示用)
    var audioStatus = "オフ"
    var motionStatus = "オフ"

    /// 設定。画面から直接書き換えてよい(毎フレーム、エンジンに反映されます)。
    /// 保存は ContentView の onChange から saveSettings() を呼んで行います。
    var settings: KeyboardSettings

    // MARK: 内部で使うもの(View から監視する必要がないので @ObservationIgnored)

    /// カメラ(通常)
    @ObservationIgnored let camera = CameraManager()
    /// カメラ(LiDAR 搭載機のみ。ARKit で深度も取る)。非対応機では nil
    @ObservationIgnored let depthCamera: DepthCameraManager? = DepthCameraManager.isSupported ? DepthCameraManager() : nil
    /// 今 LiDAR 用のカメラを使っているか
    var isUsingDepthCamera = false
    /// 計算を担当するエンジン
    @ObservationIgnored private let engine: KeyboardEngine
    /// 触覚フィードバック(軽い「コツッ」)
    @ObservationIgnored private let haptics = UIImpactFeedbackGenerator(style: .light)
    /// 完了時の触覚フィードバック(「ブブッ」)
    @ObservationIgnored private let notificationHaptics = UINotificationFeedbackGenerator()
    /// マイク(音のオンセット)
    @ObservationIgnored private let audioSensor = AudioOnsetSensor()
    /// 加速度センサー(本体の振動)
    @ObservationIgnored private let motionSensor = MotionSensor()

    /// FPS の計算
    @ObservationIgnored private var fpsCounter = FPSCounter()
    /// タップログの通し番号
    @ObservationIgnored private var tapLogCounter = 0
    /// 速度グラフに残す時間(秒)
    static let signalHistoryDuration = 2.0
    /// タップログに残す件数
    static let tapLogLimit = 12

    /// 当たり判定の地図を最後に計算したときの条件(同じなら計算し直さない)
    @ObservationIgnored private var hitMapSignature = ""
    /// 言語モデルを作ったときの n
    @ObservationIgnored private var languageModelOrder = 0

    /// UserDefaults に保存するときのキー(名前)
    private static let settingsKey = "KeyboardSettings.v1"
    private static let calibrationKey = "CalibrationResult.v1"

    init() {
        let loaded = Self.loadSettings()
        settings = loaded
        engine = KeyboardEngine(settings: loaded)
        loadLanguageModels()

        // 前回のキャリブレーションがあれば再利用する(毎回やり直さなくてよいように)
        if let saved = Self.loadCalibration() {
            engine.setCalibration(saved)
            calibration = saved
            keys = engine.keys
        }

        // カメラから1コマ届くたびに handle(_:) を呼んでもらう。
        // [weak self] にするのは、ViewModel → camera → クロージャ → ViewModel という
        // 「循環参照」(お互いを離さずメモリが解放されない状態)を防ぐためです。
        camera.onFrame = { [weak self] frame in
            self?.handle(frame)
        }
        depthCamera?.onFrame = { [weak self] frame in
            self?.handle(frame)
        }
        audioSensor.onUpdate = { [weak self] update in
            self?.handleAudio(update)
        }
        motionSensor.onUpdate = { [weak self] update in
            self?.handleMotion(update)
        }
    }

    /// アプリに同梱した学習用テキスト(自作のコーパス)から言語モデルを作る
    private func loadLanguageModels() {
        func corpus(_ name: String) -> String? {
            guard let url = Bundle.main.url(forResource: "corpus_\(name)", withExtension: "txt") else {
                print("[KeyboardViewModel] corpus_\(name).txt が見つかりません")
                return nil
            }
            return try? String(contentsOf: url, encoding: .utf8)
        }
        engine.settings = settings
        engine.setLanguageCorpora(english: corpus("english"), romaji: corpus("romaji"))
        languageModelOrder = settings.decoder.lmOrder
    }

    /// 言語モデルの文脈(直前の入力)。改行はスペースとして扱う
    private var languageContext: String {
        String(typedText.suffix(12)).replacingOccurrences(of: "\n", with: " ")
    }

    /// 当たり判定の地図を、必要なときだけ計算し直す
    private func updateHitMapsIfNeeded() {
        guard settings.overlayMode == .hitMap, calibration != nil else {
            if !hitMaps.isEmpty { hitMaps = [:] }
            hitMapSignature = ""
            return
        }
        // 文脈・キー・デコーダーの設定が同じなら、地図も同じなので計算しない
        let signature = "\(languageContext)|\(settings.decoder)|\(settings.features.languageModel)|\(settings.keyScale)|\(calibration?.createdAt.timeIntervalSince1970 ?? 0)"
        guard signature != hitMapSignature else { return }
        hitMapSignature = signature
        engine.context = languageContext
        var maps: [Chirality: HitMap] = [:]
        for chirality in Chirality.allCases {
            maps[chirality] = engine.hitMap(for: chirality)
        }
        hitMaps = maps
    }

    /// 今使うべきカメラ(設定で LiDAR がオンで、対応機なら ARKit 版)
    private var activeSource: FrameSource {
        if isUsingDepthCamera, let depthCamera { return depthCamera }
        return camera
    }

    /// 画面が表示されたときに呼ぶ
    func start() {
        isUsingDepthCamera = settings.useLiDAR && depthCamera != nil
        activeSource.start { [weak self] status in
            self?.cameraStatus = status
            // カメラが動き出してから、マイク・加速度センサーを始める
            // (カメラが使えない環境で、マイクの許可だけを聞かないように)
            if status == .running { self?.applySensorSettings() }
        }
        // 触覚フィードバックの準備(最初の1回が遅れないように、あらかじめエンジンを起こしておく)
        haptics.prepare()
        // キーボードとして使っている間は、画面が自動で消えないようにする
        UIApplication.shared.isIdleTimerDisabled = true
    }

    /// 画面が消えたとき・バックグラウンドに入ったときに呼ぶ
    func stop() {
        activeSource.stop()
        audioSensor.stop()
        motionSensor.stop()
        audioStatus = "オフ"
        motionStatus = "オフ"
        UIApplication.shared.isIdleTimerDisabled = false
    }

    /// 設定に合わせて、マイク・加速度センサーを動かしたり止めたりする(何度呼んでもよい)
    func applySensorSettings() {
        guard cameraStatus == .running else { return }
        // マイク
        if settings.features.audioOnset {
            audioSensor.updateConfig(settings.audioOnset)
            if !audioSensor.isRunning {
                audioStatus = "開始中…"
                audioSensor.start(config: settings.audioOnset) { [weak self] result in
                    switch result {
                    case .success: self?.audioStatus = "動作中"
                    case .failure(let error): self?.audioStatus = error.localizedDescription
                    }
                }
            }
        } else if audioSensor.isRunning {
            audioSensor.stop()
            audioStatus = "オフ"
        }
        // 加速度センサー(振動の補助を使うとき、または記録モードのとき)
        if settings.features.motionAssist || isRecording {
            motionSensor.updateConfig(settings.motionOnset)
            if !motionSensor.isRunning {
                if MotionSensor.isAvailable {
                    motionSensor.start(config: settings.motionOnset)
                    motionStatus = "動作中"
                } else {
                    motionStatus = "この端末では使えません"
                }
            }
        } else if motionSensor.isRunning {
            motionSensor.stop()
            motionStatus = "オフ"
        }
    }

    /// LiDAR の設定が変わったら、カメラを切り替える
    /// (AVCaptureSession と ARSession は同時に同じカメラを使えないので、片方を止めてから始める)
    func applyCameraSource() {
        let wantsDepth = settings.useLiDAR && depthCamera != nil
        guard wantsDepth != isUsingDepthCamera else { return }
        activeSource.stop()
        start()
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
        let defaults = KeyboardSettings.defaults(for: .knee)
        // 初回起動なら、膝モードの初期値から始める
        guard let data = UserDefaults.standard.data(forKey: settingsKey) else { return defaults }
        // アプリを更新して設定の項目が増えると、古い保存データには新しい項目が無いので
        // そのままでは読み込みに失敗する。そこで「初期値の JSON」に「保存データの JSON」を重ねてから読む。
        // (保存データにある項目は保存データの値、無い項目は初期値になる)
        guard let defaultData = try? JSONEncoder().encode(defaults),
              let base = try? JSONSerialization.jsonObject(with: defaultData) as? [String: Any],
              let saved = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let mergedData = try? JSONSerialization.data(withJSONObject: Self.merge(base, saved)),
              let settings = try? JSONDecoder().decode(KeyboardSettings.self, from: mergedData) else {
            return defaults
        }
        return settings
    }

    /// 辞書を重ねる(入れ子の辞書は中まで重ねる)
    private static func merge(_ base: [String: Any], _ overlay: [String: Any]) -> [String: Any] {
        var result = base
        for (key, value) in overlay {
            if let baseChild = base[key] as? [String: Any], let overlayChild = value as? [String: Any] {
                result[key] = merge(baseChild, overlayChild)
            } else {
                result[key] = value
            }
        }
        return result
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

    /// 保存したキャリブレーションを消す
    func deleteCalibration() {
        engine.setCalibration(nil)
        calibration = nil
        keys = [:]
        UserDefaults.standard.removeObject(forKey: Self.calibrationKey)
    }

    private func saveCalibration(_ result: CalibrationResult) {
        if let data = try? JSONEncoder().encode(result) {
            UserDefaults.standard.set(data, forKey: Self.calibrationKey)
        }
    }

    private static func loadCalibration() -> CalibrationResult? {
        guard let data = UserDefaults.standard.data(forKey: calibrationKey) else { return nil }
        return try? JSONDecoder().decode(CalibrationResult.self, from: data)
    }

    // MARK: 練習モード

    /// 経過時間の計算に使う「今の時刻」(端末起動からの秒数。時計の変更に影響されない)
    var now: Double { ProcessInfo.processInfo.systemUptime }

    func startPractice() {
        practice = PracticeSession()
    }

    func stopPractice() {
        practice = nil
    }

    func nextPracticeSentence() {
        practice?.next()
    }

    // MARK: テキスト編集(画面のボタンから呼ぶ)

    func insert(_ text: String) {
        typedText += text
        practice?.input(text, at: now)
    }

    func backspace() {
        practice?.backspace()
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
        engine.context = languageContext
        if settings.decoder.lmOrder != languageModelOrder {
            loadLanguageModels()
        }
        // キーの大きさが変わったときなど、キーが作り直されていたら画面にも反映
        if engine.keys != keys {
            keys = engine.keys
        }

        imageSize = frame.imageSize
        fps = fpsCounter.tick(at: frame.timestamp)
        detectedHandCount = frame.hands.count
        let output = engine.process(frame, now: now)
        hands = output.hands
        layoutFrames = output.layoutFrames
        hoveredKeyIDs = output.hoveredKeyIDs
        syncCalibrationState()
        if let result = output.calibrationFinished {
            calibration = result
            keys = engine.keys
            saveCalibration(result)
            notificationHaptics.notificationOccurred(.success)
        }
        handleTapResults(output.taps)
        recordDebugInfo(output)
        updateHitMapsIfNeeded()
    }

    /// マイクの解析結果を受け取る(メインスレッド)
    private func handleAudio(_ update: AudioUpdate) {
        engine.settings = settings
        engine.context = languageContext
        let results = engine.ingestOnsets(update.onsets, source: .audio, coveredUntil: update.coveredUntil, now: now)
        handleTapResults(results)
        guard settings.showDebug else {
            if !audioHistory.isEmpty { audioHistory.removeAll() }
            return
        }
        audioHistory += update.features
        recentOnsets += update.onsets
        let oldest = update.coveredUntil - Self.signalHistoryDuration
        audioHistory.removeAll { $0.time < oldest }
        recentOnsets.removeAll { $0.time < oldest }
        recentVisionTapTimes.removeAll { $0 < oldest }
    }

    /// 加速度センサーの解析結果を受け取る(メインスレッド)
    private func handleMotion(_ update: MotionUpdate) {
        engine.settings = settings
        engine.context = languageContext
        let results = engine.ingestOnsets(update.onsets, source: .motion, coveredUntil: update.coveredUntil, now: now)
        handleTapResults(results)
        if settings.showDebug {
            recentOnsets += update.onsets
        }
    }

    /// 確定したタップをまとめて処理する
    private func handleTapResults(_ results: [TapResult]) {
        for tap in results {
            handleTap(tap)
            tapLogCounter += 1
            tapLog.insert(TapLogEntry(id: tapLogCounter, result: tap), at: 0)
            if settings.showDebug {
                recentVisionTapTimes.append(tap.event.timestamp)
            }
        }
        if tapLog.count > Self.tapLogLimit {
            tapLog.removeLast(tapLog.count - Self.tapLogLimit)
        }
    }

    /// デバッグ表示用の記録(表示していないときは、グラフの記録を省いて少しでも軽くする)
    private func recordDebugInfo(_ output: EngineOutput) {
        guard settings.showDebug else {
            if !signalHistory.isEmpty { signalHistory.removeAll() }
            return
        }
        if let sample = output.signalSample {
            // 指が切り替わったり時間が巻き戻ったりしたら、グラフを描き直す
            if let last = signalHistory.last, sample.timestamp < last.timestamp {
                signalHistory.removeAll()
            }
            signalHistory.append(sample)
            let oldest = sample.timestamp - Self.signalHistoryDuration
            signalHistory.removeAll { $0.timestamp < oldest }
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
        if settings.hapticsEnabled || settings.soundEnabled {
            // 自分で出した音・振動を、マイクや加速度センサーが「次のタップ」と間違えないようにする
            engine.noteFeedback(at: now)
        }
    }

    private func syncCalibrationState() {
        calibrationPhase = engine.calibrator.phase
        calibrationMessage = engine.calibrator.message
    }
}
