import AVFoundation
import Accelerate

/// マイクの解析結果(メインスレッドに届ける)
struct AudioUpdate {
    /// 512 サンプル(約 10ms)ごとの特徴
    var features: [AudioFeature]
    /// 見つかったオンセット(音の立ち上がり)
    var onsets: [OnsetEvent]
    /// どの時刻までの音を解析し終えたか
    var coveredUntil: Double
}

/// マイクの音から「叩いた瞬間の音の立ち上がり(オンセット)」を見つけるクラス。
///
/// ## 流れ
/// 1. AVAudioEngine の入力(マイク)に「タップ」(音を横取りして受け取る仕組み)を付ける。
///    ※ iOS は要求したサイズより大きい塊(例: 4800 サンプル = 0.1 秒)で音を渡してくることがあるので、
///      受け取った塊を自分で 512 サンプル(48kHz で約 10.7ms)ずつに区切って解析する。
/// 2. 区間ごとに Accelerate(高速な数値計算ライブラリ)で
///    - 窓関数(ハン窓)を掛ける … 区切りの端で音が急に切れることによる余計な周波数成分を減らすため
///    - FFT(DFT)で周波数ごとの強さを求める
///    - 「スペクトルの増え方(spectral flux)」= 前の区間より強くなった成分の合計 を計算する
///      (机を叩く「パチッ」は、いろいろな周波数が一気に強くなるので flux が跳ね上がる)
/// 3. flux を OnsetDetector(適応しきい値)に入れて、立ち上がりを見つける。
///
/// ## 時刻
/// AVAudioTime の hostTime を秒に直すと、カメラの撮影時刻と同じ「端末起動からの秒数」になる。
/// これで、カメラのタップ候補と音を同じ時間軸で比べられる。
final class AudioOnsetSensor {
    /// 解析結果を(メインスレッドで)受け取るクロージャ
    var onUpdate: ((AudioUpdate) -> Void)?

    private let engine = AVAudioEngine()
    /// 解析は音声スレッド(遅れると音が途切れる大事なスレッド)ではなく、専用のキューで行う
    private let analysisQueue = DispatchQueue(label: "ARKeyboard.audio.analysis", qos: .userInitiated)

    private let hopSize = 512
    private var sampleRate: Double = 48_000
    private(set) var isRunning = false

    // ↓ analysisQueue の中でだけ使う
    private var detector = OnsetDetector(source: .audio)
    private let window: [Float]
    private let dft: vDSP.DFT<Float>?
    private let zeros: [Float]
    private var previousMagnitudes: [Float]
    private var pendingSamples: [Float] = []
    private var pendingStartTime: Double = 0

    init() {
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: hopSize, isHalfWindow: false)
        dft = vDSP.DFT(count: hopSize, direction: .forward, transformType: .complexComplex, ofType: Float.self)
        zeros = [Float](repeating: 0, count: hopSize)
        previousMagnitudes = [Float](repeating: 0, count: hopSize / 2)
    }

    /// マイクが使える環境か(シミュレーターでは使わない)
    static var isAvailable: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return AVAudioSession.sharedInstance().isInputAvailable
        #endif
    }

    /// オンセット検出の設定を変える
    func updateConfig(_ config: OnsetDetectorConfig) {
        analysisQueue.async { [weak self] in
            self?.detector.config = config
        }
    }

    /// マイクの許可を確認して、録音(解析)を始める
    /// - Parameter completion: 成功したか、失敗した理由(メインスレッド)
    func start(config: OnsetDetectorConfig, completion: @escaping (Result<Void, Error>) -> Void) {
        guard !isRunning else { completion(.success(())); return }
        guard Self.isAvailable else {
            completion(.failure(SensorError.unavailable("マイクが使えません")))
            return
        }
        updateConfig(config)
        // iOS 17 からの許可の聞き方(文言は Info.plist の NSMicrophoneUsageDescription)
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                guard granted else {
                    completion(.failure(SensorError.denied("マイクが許可されていません")))
                    return
                }
                do {
                    try self.startEngine()
                    completion(.success(()))
                } catch {
                    completion(.failure(error))
                }
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func startEngine() throws {
        let session = AVAudioSession.sharedInstance()
        // playAndRecord: 録音しながらクリック音も鳴らすため
        // measurement: 自動音量調整などの加工を切る(叩いた音の立ち上がりを、なまらせないため)
        // defaultToSpeaker: measurement だと小さい受話口から鳴るので、スピーカーから鳴らす
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.mixWithOthers, .defaultToSpeaker])
        // 1回に受け渡す音の長さを短くしてほしい、というお願い(必ず守られるとは限らない)
        try session.setPreferredIOBufferDuration(0.005)
        // ⚠️ 録音中、iOS は標準で触覚フィードバックとシステム音を止めてしまう。それを許可する
        try session.setAllowHapticsAndSystemSoundsDuringRecording(true)
        try session.setActive(true)

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        sampleRate = format.sampleRate
        let sampleRate = self.sampleRate
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: AVAudioFrameCount(hopSize * 2), format: format) { [weak self] buffer, when in
            // ここは音声スレッド。重い処理をせず、コピーして解析キューに渡すだけにする
            guard let self, let channel = buffer.floatChannelData?[0] else { return }
            let count = Int(buffer.frameLength)
            let samples = Array(UnsafeBufferPointer(start: channel, count: count))
            let startTime: Double
            if when.isHostTimeValid {
                startTime = AVAudioTime.seconds(forHostTime: when.hostTime)
            } else {
                startTime = ProcessInfo.processInfo.systemUptime - Double(count) / sampleRate
            }
            self.analysisQueue.async { [weak self] in
                self?.analyze(samples, startTime: startTime)
            }
        }
        engine.prepare()
        try engine.start()
        isRunning = true
    }

    /// 届いた音の塊を 512 サンプルずつに区切って解析する(analysisQueue)
    private func analyze(_ samples: [Float], startTime: Double) {
        // 前の塊の続きでなければ(時間が飛んだら)、溜めていた半端な分は捨てる
        let expectedStart = pendingStartTime + Double(pendingSamples.count) / sampleRate
        if pendingSamples.isEmpty || abs(startTime - expectedStart) > 0.02 {
            pendingSamples = []
            pendingStartTime = startTime
        }
        pendingSamples += samples

        var features: [AudioFeature] = []
        var onsets: [OnsetEvent] = []
        while pendingSamples.count >= hopSize {
            let hop = Array(pendingSamples[0..<hopSize])
            pendingSamples.removeFirst(hopSize)
            // 区間の真ん中の時刻
            let time = pendingStartTime + Double(hopSize) / 2 / sampleRate
            pendingStartTime += Double(hopSize) / sampleRate

            var feature = computeFeature(hop, time: time)
            if let onset = detector.process(value: feature.flux, time: time) {
                onsets.append(onset)
            }
            feature.threshold = detector.lastThreshold
            features.append(feature)
        }
        guard !features.isEmpty else { return }
        let update = AudioUpdate(features: features, onsets: onsets, coveredUntil: pendingStartTime)
        DispatchQueue.main.async { [weak self] in
            self?.onUpdate?(update)
        }
    }

    /// 1区間の特徴(音の大きさとスペクトルの増え方)を Accelerate で計算する
    private func computeFeature(_ hop: [Float], time: Double) -> AudioFeature {
        let rms = Double(vDSP.rootMeanSquare(hop))
        guard let dft else { return AudioFeature(time: time, rms: rms, flux: 0) }

        let windowed = vDSP.multiply(hop, window)
        let spectrum = dft.transform(inputReal: windowed, inputImaginary: zeros)
        // 周波数ごとの強さ(大きさ)。実数の信号なので、前半分だけ見れば十分
        let half = hopSize / 2
        var magnitudes = [Float](repeating: 0, count: half)
        for i in 0..<half {
            let re = spectrum.real[i]
            let im = spectrum.imaginary[i]
            magnitudes[i] = (re * re + im * im).squareRoot()
        }
        // 前の区間より強くなった分だけを足す(弱くなった分は数えない)
        var flux: Float = 0
        for i in 0..<half {
            let diff = magnitudes[i] - previousMagnitudes[i]
            if diff > 0 { flux += diff }
        }
        previousMagnitudes = magnitudes
        return AudioFeature(time: time, rms: rms, flux: Double(flux) / Double(hopSize))
    }
}

/// センサーのエラー
enum SensorError: LocalizedError {
    case unavailable(String)
    case denied(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let message), .denied(let message): return message
        }
    }
}
