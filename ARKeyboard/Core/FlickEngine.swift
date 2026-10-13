import Foundation

/// フリック1回分の結果
struct FlickResult: Equatable {
    var gesture: FlickGesture
    var decode: FlickDecodeResult
    /// このフリックでいちばん確からしい入力(「゛」なら濁点などの切り替え)
    var output: String?
    /// 今の仮名の並び(句読点・空白で区切られるまで)を、この文字列に書き換える
    var rewrite: String?
    /// 書き換えの前に、末尾から消す文字数
    var replaceCount: Int
    /// 並びの上位の候補(候補の表示用)
    var nBest: [String]
}

/// フリック入力の処理(配置・切り出し・解読・並びの管理・方向の個人適応)
final class FlickEngine {
    var config = FlickConfig()
    let segmenter = FlickSegmenter()
    let beam = KanaBeamDecoder()
    /// 仮名の言語モデル
    var kanaModel: CharNGramModel?
    /// 方向のずれ(回転)を個人適応するか
    var adaptRotation = false
    /// 方式B が使えるか(音のオンセットが使える)。使えなければ方式A で動く(フォールバック)
    var contactAvailable = false
    /// 最近、機能パッドのタップが採用された時刻(方式B で、その音で始まったフリックを捨てるため)
    var recentFunctionTaps: [Double] = []

    /// 今、方式B で切り出しているか
    var usesContact: Bool { config.segmentation == .contact && contactAvailable }

    private(set) var keys: [FlickKey] = []
    /// 今の仮名の並びの、フリックごとの候補
    private var runSteps: [[FlickCandidate]] = []
    /// 並びの直前までの文脈
    private var runContext = ""
    /// 並びの上位の候補と、今どれを表示しているか
    private(set) var runNBest: [String] = []
    private var runCandidateIndex = 0
    /// 画面に表示している、今の並びの文字数
    private var displayedRunLength = 0

    /// 方向のずれの統計(指ごと: 回数、角度の誤差の合計)
    private var angleStats: [FingerID: (n: Double, sum: Double)] = [:]
    private var lastAngleRecord: (finger: FingerID, error: Double)?
    /// 方向のずれの事前分布の強さ(この回数分のデータが集まるまで、ずれ 0 を強く信じる)
    let rotationPriorStrength = 10.0

    var languageModel: ((Character, String) -> Double)? {
        guard let model = kanaModel else { return nil }
        return { c, h in model.probability(of: c, after: h) }
    }

    func rebuildKeys(calibration: CalibrationResult?) {
        guard let calibration else { keys = []; return }
        keys = Chirality.allCases.flatMap { FlickModel.makeKeys(for: calibration.hand($0), config: config) }
    }

    func reset() {
        segmenter.reset()
        endRun()
    }

    /// 指ごとの方向のずれ(ラジアン)。個人適応がオフなら 0
    func rotation(for finger: FingerID) -> Double {
        guard adaptRotation, let s = angleStats[finger] else { return 0 }
        return s.sum / (rotationPriorStrength + s.n)
    }

    /// 1フレーム分: フリックの指を追い、フリックが終わったら解読する
    /// - Returns: フリックの結果(終わったときだけ)と、指先の下のキー
    func process(hand: HandObservation, chirality: Chirality, layoutFrame: HandFrame, liveFrame: HandFrame,
                 time: Double, minConfidence: Double, context: String) -> (result: FlickResult?, hoveredKeyID: String?) {
        segmenter.config = config
        segmenter.contactMode = usesContact
        let finger = FingerID(chirality: chirality, finger: .index)
        var position: Vec2?
        var rel: Vec2?
        if let tip = hand.position(.indexTip, minConfidence: minConfidence),
           let palm = TapDetector.palmCenter(of: hand, minConfidence: minConfidence) {
            position = layoutFrame.toLocal(tip)
            let r = tip - palm
            rel = Vec2(r.dot(liveFrame.thumbward), r.dot(liveFrame.forward)) / liveFrame.scale
        }
        var hovered: String?
        if let position {
            let handKeys = keys.filter { $0.hand == chirality }
            hovered = handKeys.min { $0.center.distance(to: position) < $1.center.distance(to: position) }
                .flatMap { $0.center.distance(to: position) < max($0.size.x, $0.size.y) ? $0.id : nil }
        }
        guard let gesture = segmenter.process(finger: finger, position: position, rel: rel, time: time) else {
            return (nil, hovered)
        }
        // 方式B: 機能パッドのタップの音で始まった「動かないフリック」は、機能パッドの音だったとみなして捨てる
        recentFunctionTaps.removeAll { $0 < time - 1 }
        if usesContact, gesture.displacement.length < config.tapDistance,
           recentFunctionTaps.contains(where: { abs($0 - gesture.startTime) < config.contactFunctionGuard }) {
            return (nil, hovered)
        }
        return (handle(gesture, context: context), hovered)
    }

    /// フリック1回を解読して、今の並びを決め直す
    func handle(_ gesture: FlickGesture, context: String) -> FlickResult {
        // 候補を選び直していた並びは、その選択で確定してから次へ
        if runCandidateIndex != 0 { endRun() }
        if runSteps.isEmpty { runContext = context }
        let decode = FlickModel.decode(gesture: gesture, keys: keys, context: runContext + currentRunText,
                                       config: config, rotation: rotation(for: gesture.finger),
                                       languageModel: languageModel)
        guard let best = decode.best else {
            return FlickResult(gesture: gesture, decode: decode, output: nil, rewrite: nil, replaceCount: 0, nBest: runNBest)
        }
        recordAngle(gesture: gesture, best: best)
        runSteps.append(decode.candidates)
        let (rewrite, replace) = redecodeRun()
        let result = FlickResult(gesture: gesture, decode: decode, output: best.output, rewrite: rewrite,
                                 replaceCount: replace, nBest: runNBest)
        // 句読点で並びを区切る
        if ["、", "。", "?", "!"].contains(best.output) { endRun() }
        return result
    }

    /// 機能パッドの「゛゜小」「次の候補」を処理する(書き換えがあれば返す)
    func applyFunction(_ action: FunctionAction) -> (rewrite: String, replaceCount: Int)? {
        switch action {
        case .modifier:
            guard !runSteps.isEmpty, let modifierKey = keys.first(where: { $0.definition.isModifier }) else { return nil }
            runSteps.append([FlickCandidate(output: "゛", key: modifierKey, direction: .tap, probability: 1,
                                            logLikelihood: 0)])
            let (rewrite, replace) = redecodeRun()
            return rewrite.map { ($0, replace) }
        case .nextCandidate:
            guard runNBest.count > 1 else { return nil }
            runCandidateIndex = (runCandidateIndex + 1) % runNBest.count
            let replace = displayedRunLength
            let text = runNBest[runCandidateIndex]
            displayedRunLength = text.count
            return (text, replace)
        case .space, .newline:
            endRun()
            return nil
        case .backspace, .none:
            return nil
        }
    }

    /// 候補を直接選ぶ(画面の候補のタップ)
    func selectCandidate(_ index: Int) -> (rewrite: String, replaceCount: Int)? {
        guard index < runNBest.count else { return nil }
        runCandidateIndex = index
        let replace = displayedRunLength
        let text = runNBest[index]
        displayedRunLength = text.count
        if index != 0 { endRunKeepingDisplay() }
        return (text, replace)
    }

    /// 並びを確定する(表示はそのまま)
    private func endRunKeepingDisplay() {
        runSteps = []
        runNBest = []
        runCandidateIndex = 0
        displayedRunLength = 0
    }

    /// 削除ボタン: 並びの最後のフリックを取り消す
    func noteBackspace() {
        if !runSteps.isEmpty {
            runSteps.removeLast()
            displayedRunLength = max(0, displayedRunLength - 1)
            runNBest = runSteps.isEmpty ? [] : beam.decode(steps: runSteps, context: runContext)
        }
        // 削除されたフリックの方向は、学習から取り除く
        if let record = lastAngleRecord, var s = angleStats[record.finger] {
            s.n -= 1
            s.sum -= record.error
            angleStats[record.finger] = s
            lastAngleRecord = nil
        }
    }

    func endRun() {
        runSteps = []
        runNBest = []
        runCandidateIndex = 0
        displayedRunLength = 0
    }

    private var currentRunText: String { runNBest.first ?? "" }

    private func redecodeRun() -> (rewrite: String?, replaceCount: Int) {
        beam.languageModel = config.useLanguageModel ? languageModel : nil
        beam.lmWeight = config.lmWeight
        runNBest = Array(beam.decode(steps: runSteps, context: runContext).prefix(3))
        runCandidateIndex = 0
        let replace = displayedRunLength
        let text = runNBest.first ?? ""
        displayedRunLength = text.count
        return (text, replace)
    }

    /// 方向の個人適応: 自信のあるフリックの、測った角度と本来の方向の差を記録する
    private func recordAngle(gesture: FlickGesture, best: FlickCandidate) {
        guard best.probability >= 0.9, let mu = best.direction.angle else { return }
        let keyboardRight: Double = gesture.finger.chirality == .left ? 1 : -1
        let angle = atan2(gesture.displacement.y, gesture.displacement.x * keyboardRight)
        var error = angle - mu
        while error > Double.pi { error -= 2 * Double.pi }
        while error < -Double.pi { error += 2 * Double.pi }
        var s = angleStats[gesture.finger] ?? (0, 0)
        s.n += 1
        s.sum += error
        angleStats[gesture.finger] = s
        lastAngleRecord = (gesture.finger, error)
    }
}
