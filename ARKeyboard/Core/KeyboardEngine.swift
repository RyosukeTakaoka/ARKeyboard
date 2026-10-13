import Foundation

/// タップと、それで押されたキー
struct TapResult: Equatable {
    /// カメラが見つけたタップの候補
    var event: TapEvent
    /// 「いつ・どの指・どこ」をまとめたタップイベント(キャリブレーション前は nil)
    var touch: TouchEvent? = nil
    /// 押されたキー(却下されたとき、キャリブレーション前、キーから遠すぎるときは nil)
    var key: Key?
    /// キーが決まらなかった理由など(デバッグログ用)
    var note: String?
    /// LiDAR: 面に触れていたときの高さから、どれだけ持ち上がっていたか(メートル)。測れなければ nil
    var heightAboveSurface: Double? = nil
    /// 対応づけた音のオンセットの時刻 − カメラのタップ時刻(秒)。時間窓の調整に使う
    var audioOffset: Double? = nil
    /// 対応づけた振動のオンセットの時刻 − カメラのタップ時刻(秒)
    var motionOffset: Double? = nil
    /// デコーダーの結果(キーごとの確率)。デコーダーを使わないときは nil
    var decode: DecodeResult? = nil
}

/// 融合の結果を待っている候補に付けておく情報
struct TapCandidate {
    var event: TapEvent
    var touch: TouchEvent?
    var heightAboveSurface: Double?
}

/// 1フレーム処理した結果(ViewModel が画面に反映する)
struct EngineOutput {
    /// 左右を割り当てた手
    var hands: [Chirality: HandObservation] = [:]
    /// キー配置の基準にしている手の座標系(画面にキーを描くのに使う)
    var layoutFrames: [Chirality: HandFrame] = [:]
    /// 指先の下にあるキーの ID(光らせる)
    var hoveredKeyIDs: Set<String> = []
    /// このフレームで起きたタップ
    var taps: [TapResult] = []
    /// デバッググラフ用の、1本の指の速度
    var signalSample: FingerSignalSample?
    /// このフレームでキャリブレーションが完了したら、その結果
    var calibrationFinished: CalibrationResult?
}

/// キーボードの「頭脳」。カメラにも画面にも依存しない純粋なロジックだけを持ちます。
///
/// VisionFrame(手の認識結果)を1つ受け取るたびに、
///   左右の割り当て → 手の座標系 → キャリブレーション → 指先とキーの対応
///   → タップ候補(カメラ)→ 音・振動との融合(保留・確定)→ キーの決定
/// の順に処理して、EngineOutput を返します。
/// 音・振動のオンセットは ingestOnsets(...) で別に受け取ります。
/// UI に依存しないので、単体テストで動作を確かめられます。
final class KeyboardEngine {
    var settings: KeyboardSettings {
        didSet {
            // キーの大きさが変わったらキーを作り直す
            if settings.keyScale != oldValue.keyScale { rebuildKeys() }
        }
    }

    /// キャリブレーション
    let calibrator = Calibrator()
    /// 現在のキャリブレーション結果(未実施なら nil)
    private(set) var calibration: CalibrationResult?
    /// 手ごとのキー(手の座標で表したもの)
    private(set) var keys: [Chirality: [Key]] = [:]
    /// タップ判定(カメラ)
    let tapDetector = TapDetector()
    /// カメラの候補と音・振動を突き合わせる
    let fusion = SensorFusion<TapCandidate>()
    /// キーを確率で選ぶデコーダー(空間タッチモデル × 言語モデル)
    let decoder = TapDecoder()
    /// 直前までに入力された文字列(言語モデルの文脈)。ViewModel が毎回セットする
    var context: String = ""
    /// 言語モデル
    private var languageModels: [DecoderLanguage: CharNGramModel] = [:]
    /// 最後にキーが入力された時刻(入力の速さを測るため)
    private var lastKeyTime: Double?

    /// 手ごとの「平滑化した」手の座標系(手ぶれでキー配置が震えないようにするため)
    private var smoothedFrames: [Chirality: HandFrame] = [:]

    /// キャリブレーション中に集めた「指先の深さ − 手のひらの深さ」(LiDAR モードのみ)
    private var calibrationDepthSamples: [FingerID: [Double]] = [:]

    init(settings: KeyboardSettings = KeyboardSettings()) {
        self.settings = settings
    }

    /// 言語モデルを作る(学習用のテキストから)。order が変わったときも呼ぶ。
    func setLanguageCorpora(english: String?, romaji: String?) {
        let order = settings.decoder.lmOrder
        languageModels = [:]
        if let english { languageModels[.english] = CharNGramModel(text: english, order: order) }
        if let romaji { languageModels[.romaji] = CharNGramModel(text: romaji, order: order) }
        syncDecoderSettings()
    }

    /// デコーダーの設定と、使う言語モデルを反映する
    private func syncDecoderSettings() {
        decoder.config = settings.decoder
        let english = languageModels[.english], romaji = languageModels[.romaji]
        switch settings.decoder.language {
        case .english:
            decoder.languageModel = english.map { model in { c, h in model.probability(of: c, after: h) } }
        case .romaji:
            decoder.languageModel = romaji.map { model in { c, h in model.probability(of: c, after: h) } }
        case .mixed:
            let parts = [english, romaji].compactMap { $0 }.map { (model: $0, weight: 1.0) }
            let mixed = MixedLanguageModel(models: parts)
            decoder.languageModel = parts.isEmpty ? nil : { c, h in mixed.probability(of: c, after: h) }
        }
    }

    /// 当たり判定の地図(当たり判定ビュー用)
    func hitMap(for chirality: Chirality) -> HitMap? {
        guard let handKeys = keys[chirality] else { return nil }
        syncDecoderSettings()
        return decoder.hitMap(keys: handKeys, context: context,
                              useLanguageModel: settings.features.languageModel)
    }

    func startCalibration() {
        calibrator.start()
        tapDetector.reset()
        _ = fusion.resolve(now: .infinity)  // 保留中の候補は捨てる
        calibrationDepthSamples = [:]
    }

    func setCalibration(_ result: CalibrationResult?) {
        calibration = result
        rebuildKeys()
    }

    private func rebuildKeys() {
        keys = [:]
        guard let calibration else { return }
        for chirality in Chirality.allCases {
            keys[chirality] = KeyLayout.makeKeys(for: calibration.hand(chirality), keyScale: settings.keyScale)
        }
    }

    /// キー配置の基準にする手の座標系
    /// - 面に固定: キャリブレーションした瞬間の座標系(ずっと同じ)
    /// - 手に追従: 今の手の座標系(平滑化したもの)
    func layoutFrame(for chirality: Chirality) -> HandFrame? {
        guard let calibration else { return nil }
        switch settings.anchor {
        case .fixed: return calibration.hand(chirality).frame
        case .followHand: return smoothedFrames[chirality]
        }
    }

    /// 画像上の指先の位置から、押しているキーを探す
    func key(atImagePoint point: Vec2, finger: FingerID) -> Key? {
        guard let frame = layoutFrame(for: finger.chirality), let handKeys = keys[finger.chirality] else {
            return nil
        }
        return KeyLayout.nearestKey(to: frame.toLocal(point),
                                    finger: finger.finger,
                                    in: handKeys,
                                    restrictToFinger: settings.restrictKeysToFinger,
                                    maxDistance: settings.maxKeyDistance)?.key
    }

    /// 1フレーム分の処理
    /// - Parameters:
    ///   - frame: 手の認識結果
    ///   - now: 今の時刻(秒、端末起動から)。省略するとフレームの撮影時刻を使う。
    ///     音のデータを待つ時間の計算に使うので、実機では処理した瞬間の時刻を渡す。
    func process(_ frame: VisionFrame, now: Double? = nil) -> EngineOutput {
        var output = EngineOutput()
        let now = max(now ?? frame.timestamp, frame.timestamp)
        let hands = assignHands(frame.hands)
        output.hands = hands

        // 手の座標系を作り、前のフレームの値となめらかにつなぐ
        for chirality in Chirality.allCases {
            if let hand = hands[chirality],
               let live = HandFrame(hand: hand, minConfidence: settings.minConfidence) {
                if let previous = smoothedFrames[chirality] {
                    smoothedFrames[chirality] = previous.smoothed(toward: live, alpha: 1 - settings.layoutSmoothing)
                } else {
                    smoothedFrames[chirality] = live
                }
            } else {
                // 手が見えなくなったら、古い座標系は捨てる(再び見えたときに古い位置から動き出さないように)
                smoothedFrames[chirality] = nil
            }
        }

        // キャリブレーション中は、それだけを行う
        if calibrator.isActive {
            recordCalibrationDepths(hands: hands, frame: frame)
            if var result = calibrator.process(hands: hands, timestamp: frame.timestamp) {
                result.restRelativeDepths = restDepthsFromCalibration()
                setCalibration(result)
                output.calibrationFinished = result
            }
            return output
        }

        // 指先の下にあるキーを探す(画面で光らせる)
        for chirality in Chirality.allCases {
            guard let hand = hands[chirality], let layout = layoutFrame(for: chirality) else { continue }
            output.layoutFrames[chirality] = layout
            for finger in Finger.allCases {
                guard let tip = hand.position(Joint.tip(of: finger), minConfidence: settings.minConfidence),
                      let key = key(atImagePoint: tip, finger: FingerID(chirality: chirality, finger: finger)) else {
                    continue
                }
                output.hoveredKeyIDs.insert(key.id)
            }
        }

        // タップ判定(設定は毎フレーム反映するので、スライダーを動かすとすぐ効く)
        tapDetector.parameters = settings.tap
        tapDetector.sensitivity = settings.sensitivity
        tapDetector.minConfidence = settings.minConfidence
        var tapInput: [Chirality: (observation: HandObservation, frame: HandFrame)] = [:]
        for chirality in Chirality.allCases {
            // 「下向き」と「手の大きさ」は、今の手の座標系(平滑化済み)から求める
            if let hand = hands[chirality], let handFrame = smoothedFrames[chirality] {
                tapInput[chirality] = (hand, handFrame)
            }
        }
        let detection = tapDetector.process(hands: tapInput, timestamp: frame.timestamp,
                                            observedFinger: settings.debugFinger)
        output.signalSample = detection.sample

        syncFusionSettings()
        for event in detection.taps {
            if let rejected = addCandidate(event, hands: hands, frame: frame) {
                output.taps.append(rejected)
            }
        }
        output.taps += resolvePending(now: now)
        return output
    }

    /// 音・振動のオンセットを受け取る(マイク・加速度センサーから、メインスレッドで)。
    /// 保留していた候補が確定したら、その結果を返す。
    func ingestOnsets(_ events: [OnsetEvent], source: OnsetEvent.Source, coveredUntil: Double, now: Double) -> [TapResult] {
        syncFusionSettings()
        fusion.addOnsets(events, source: source, coveredUntil: coveredUntil, now: now)
        return resolvePending(now: now)
    }

    /// クリック音や触覚を出したことを知らせる(自分の音・振動をタップと間違えないように)
    func noteFeedback(at time: Double) {
        fusion.muteFeedback(at: time)
    }

    private func syncFusionSettings() {
        fusion.config = settings.fusion
        fusion.useAudio = settings.features.audioOnset
        fusion.useMotion = settings.features.motionAssist
    }

    /// カメラのタップ候補から TouchEvent を作り、融合の保留に加える。
    /// その場で却下できるとき(LiDAR で空中と分かった)は、却下の結果を返す。
    private func addCandidate(_ event: TapEvent, hands: [Chirality: HandObservation], frame: VisionFrame) -> TapResult? {
        // LiDAR の補助: 指が「面に触れていた高さ」まで下りていなければ、空中で止めただけとみなす
        let height = heightAboveSurface(finger: event.finger, hands: hands, frame: frame)
        if settings.useLiDAR, let height, height > settings.lidarTolerance {
            return TapResult(event: event, touch: nil, key: nil,
                             note: String(format: "LiDAR: 面から%.1fcm上", height * 100),
                             heightAboveSurface: height)
        }
        var touch = makeTouch(from: event)
        if settings.useLiDAR, height != nil { touch?.evidence.insert(.depth) }
        fusion.addCandidate(time: event.timestamp,
                            payload: TapCandidate(event: event, touch: touch, heightAboveSurface: height))
        return nil
    }

    /// カメラの候補から「いつ・どの指・どこ」のタップイベントを作る(キャリブレーション前は nil)
    func makeTouch(from event: TapEvent) -> TouchEvent? {
        guard let calibration, let frame = layoutFrame(for: event.finger.chirality) else { return nil }
        let hand = calibration.hand(event.finger.chirality)
        // 位置の不確かさ: キーの大きさの 3 割程度のばらつきがあると仮定(個人適応で更新される)
        let sigma = settings.decoder.measurementSigma
        let covariance = Covariance2.diagonal(sigmaX: sigma * hand.keyPitch * settings.keyScale,
                                              sigmaY: sigma * hand.rowPitch * settings.keyScale)
        // カメラの確からしさ: しきい値ぎりぎりなら 0.5、しきい値の2倍以上なら 0.95
        let ratio = event.peakSpeed / max(tapDetector.effectiveDownSpeed, 1e-6)
        let visionConfidence = min(max(0.5 + (ratio - 1) * 0.45, 0.05), 0.95)
        return TouchEvent(time: event.timestamp,
                          finger: event.finger,
                          surfaceLocation: frame.toLocal(event.tipPosition),
                          locationCovariance: covariance,
                          confidence: visionConfidence,
                          imagePosition: event.tipPosition,
                          evidence: [.vision])
    }

    /// 融合で確定した候補を、入力結果に変換する
    private func resolvePending(now: Double) -> [TapResult] {
        syncDecoderSettings()
        // 同じ回にまとめて確定したタップは、前のタップの文字も文脈に含める
        var runningContext = context
        return fusion.resolve(now: now).map { decision in
            var result = TapResult(event: decision.payload.event,
                                   touch: decision.payload.touch,
                                   key: nil,
                                   note: decision.note,
                                   heightAboveSurface: decision.payload.heightAboveSurface,
                                   audioOffset: decision.audio.map { $0.time - decision.time },
                                   motionOffset: decision.motion.map { $0.time - decision.time })
            guard decision.accepted else { return result }
            guard var touch = result.touch else {
                result.note = "未キャリブレーション"
                return result
            }
            // 音・振動の裏付けがあれば、確からしさを上げる(どれか1つでも当たっていれば、の確率)
            for onset in [decision.audio, decision.motion].compactMap({ $0 }) {
                touch.evidence.insert(onset.source == .audio ? .audio : .motion)
                let c = min(max(0.5 + (onset.strength - 1) * 0.25, 0.3), 0.95)
                touch.confidence = 1 - (1 - touch.confidence) * (1 - c)
            }
            result.touch = touch
            let chosen = chooseKey(for: touch, context: runningContext)
            result.key = chosen.key
            result.decode = chosen.decode
            if let key = chosen.key {
                runningContext += key.output
                lastKeyTime = touch.time
            } else if result.note == nil {
                result.note = "キーの範囲外"
            }
            return result
        }
    }

    /// タップイベントから入力するキーを決める
    /// - デコーダーがオフ: いちばん近いキー
    /// - デコーダーがオン: 位置の分布 × 指の制約 × 言語モデル の事後確率が最大のキー
    private func chooseKey(for touch: TouchEvent, context: String) -> (key: Key?, decode: DecodeResult?) {
        guard let handKeys = keys[touch.finger.chirality] else { return (nil, nil) }
        // どちらの方式でも、キーから遠すぎるタップは「範囲外」にする
        let nearest = KeyLayout.nearestKey(to: touch.surfaceLocation,
                                           finger: touch.finger.finger,
                                           in: handKeys,
                                           restrictToFinger: settings.restrictKeysToFinger,
                                           maxDistance: settings.maxKeyDistance)?.key
        guard let nearest else { return (nil, nil) }
        guard settings.features.decoder else { return (nearest, nil) }

        let interval = lastKeyTime.map { touch.time - $0 }
        let result = decoder.decode(location: touch.surfaceLocation,
                                    measurementCovariance: touch.locationCovariance,
                                    finger: touch.finger,
                                    keys: handKeys,
                                    context: context,
                                    interval: interval,
                                    restrictToFinger: settings.restrictKeysToFinger,
                                    useLanguageModel: settings.features.languageModel)
        return (result.best ?? nearest, result)
    }

    // MARK: - LiDAR(深度)

    /// キャリブレーション中(指が面に触れている間)の「指先の深さ − 手のひらの深さ」を集める
    private func recordCalibrationDepths(hands: [Chirality: HandObservation], frame: VisionFrame) {
        guard let depthMap = frame.depthMap else { return }
        for (chirality, hand) in hands {
            for finger in Finger.allCases {
                guard let value = DepthAssist.relativeTipDepth(hand: hand, finger: finger, imageSize: frame.imageSize,
                                                               depthMap: depthMap, minConfidence: settings.minConfidence)
                else { continue }
                let id = FingerID(chirality: chirality, finger: finger)
                var samples = calibrationDepthSamples[id, default: []]
                samples.append(value)
                // 静止の最後の方(約1秒分)だけ使う
                if samples.count > 60 { samples.removeFirst(samples.count - 60) }
                calibrationDepthSamples[id] = samples
            }
        }
    }

    private func restDepthsFromCalibration() -> [FingerID: Double]? {
        var result: [FingerID: Double] = [:]
        for (id, samples) in calibrationDepthSamples {
            if let median = DepthMap.median(samples) { result[id] = median }
        }
        return result.isEmpty ? nil : result
    }

    /// 指先が「面に触れていたときの高さ」からどれだけ持ち上がっているか(メートル)
    private func heightAboveSurface(finger: FingerID, hands: [Chirality: HandObservation], frame: VisionFrame) -> Double? {
        guard let depthMap = frame.depthMap,
              let rest = calibration?.restRelativeDepths?[finger],
              let hand = hands[finger.chirality],
              let current = DepthAssist.relativeTipDepth(hand: hand, finger: finger.finger, imageSize: frame.imageSize,
                                                         depthMap: depthMap, minConfidence: settings.minConfidence)
        else { return nil }
        return DepthAssist.heightAboveRest(current: current, rest: rest)
    }

    /// Vision の検出結果(最大2つ)を「左手」「右手」に割り当てます。
    ///
    /// 基本は Vision の chirality(左右判定)を使います。ただし、
    /// - 判定できなかった(unknown)とき
    /// - 2つとも同じ手だと判定されたとき
    /// は、手の形(人差し指が forward のどちら側にあるか)から推定した左右で補います。
    func assignHands(_ observations: [HandObservation]) -> [Chirality: HandObservation] {
        var result: [Chirality: HandObservation] = [:]
        var unresolved: [HandObservation] = []

        for observation in observations {
            if var chirality = observation.chirality {
                if settings.swapHands { chirality = chirality.opposite }
                if result[chirality] == nil {
                    result[chirality] = observation
                    continue
                }
            }
            unresolved.append(observation)
        }

        for observation in unresolved {
            // 形からの推定(手のひらを下にして上から撮っている前提)
            var guess: Chirality? = HandFrame(hand: observation, minConfidence: settings.minConfidence)?.handedness
            if settings.swapHands { guess = guess?.opposite }
            if let guess, result[guess] == nil {
                result[guess] = observation
            } else if let free = Chirality.allCases.first(where: { result[$0] == nil }) {
                result[free] = observation
            }
        }
        return result
    }
}
