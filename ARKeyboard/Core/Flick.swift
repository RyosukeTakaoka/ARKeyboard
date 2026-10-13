import Foundation

/// 入力の方式
enum InputMode: String, Codable, CaseIterable, Identifiable {
    case qwerty
    case flick
    /// 手書き(人差し指と親指でつまんで書く → Vision の文字認識。Tier3)
    case handwriting

    var id: String { rawValue }

    var japaneseName: String {
        switch self {
        case .qwerty: return "QWERTY(英字)"
        case .flick: return "フリック(かな)"
        case .handwriting: return "手書き"
        }
    }
}

/// ジェスチャーの切り出し方
enum FlickSegmentation: String, Codable, CaseIterable, Identifiable {
    /// 方式A「エアフリック」: 接触は使わず、指先の速さだけで始まりと終わりを決める
    case air
    /// 方式B「接触フリック」: 音のオンセットを接触の始まりとし、指が止まったところを終わりとする(Tier3)
    case contact

    var id: String { rawValue }

    var japaneseName: String {
        switch self {
        case .air: return "方式A: エアフリック"
        case .contact: return "方式B: 接触フリック(音)"
        }
    }
}

/// 機能パッド(フリックパッドでない方の手)の動作
enum FunctionAction: String, Codable, CaseIterable, Identifiable {
    case space, backspace, newline, modifier, nextCandidate, none

    var id: String { rawValue }

    var japaneseName: String {
        switch self {
        case .space: return "空白"
        case .backspace: return "削除"
        case .newline: return "改行"
        case .modifier: return "゛゜小"
        case .nextCandidate: return "次の候補"
        case .none: return "なし"
        }
    }
}

/// フリック入力の設定(数値はすべて仮説。記録データで調整する)
struct FlickConfig: Codable, Equatable {
    /// フリックパッドを置く手(利き手)
    var hand: Chirality = .right
    /// 両手ともフリックパッドにする(機能パッドを使わない)
    var bothHands: Bool = false
    /// キーの大きさ(QWERTY のキー間隔に対する倍率)
    var keyScale: Double = 1.6
    var segmentation: FlickSegmentation = .air
    /// 動き出しとみなす速さ(手/秒)。キーの上へ指を「ゆっくり」移動する動きと区別するため、高めにしている
    var startSpeed: Double = 2.0
    /// 止まったとみなす速さ(手/秒)
    var endSpeed: Double = 0.8
    /// 止まりの速さをこの時間(秒)下回り続けたら、フリックの終わり。
    /// 空中タップは「下ろして戻す」途中の折り返しで一瞬遅くなるので、そこで切ると「下フリック」と間違える
    var endHold: Double = 0.03
    /// 方式B: 接触(音)からこの時間(秒)たったら、動きが止まっていなくてもフリックを終える
    var contactWindow: Double = 0.25
    /// 方式B: 機能パッドのタップの音と、この時間(秒)以内に始まった「タップ」は、機能パッドの音とみなして捨てる
    var contactFunctionGuard: Double = 0.15
    /// 方式B: 音の直後(−0.05〜+0.12 秒)の指の速さの最大がこれより遅ければ、その音は指の接触ではない
    /// (まわりの物音や、もう一方の手のタップの音)とみなす(手/秒)。キーへのゆっくりした移動(〜1.5)より上にする
    var contactMinSpeed: Double = 1.8
    /// 指先の位置のぶれ除去(One Euro フィルター)を使う。
    /// 既定はオフ: 合成データでは、ぶれが大きいとき(手の大きさの 1〜2%)は少し良くなるが、ぶれが小さいときに
    /// 動き出しの速さがなまって大きく悪くなった(docs/results-flick.md)。オンにするときは
    /// 動き出しの速さ 1.2・止まりの速さ 0.5 程度に下げる(フィルターで速さの山が低くなるため)
    var useJitterFilter: Bool = false
    /// One Euro フィルターの、止まっているときの遮断周波数(Hz)と、速さに応じた上げ幅
    var filterMinCutoff: Double = 1.5
    var filterBeta: Double = 3.0
    /// 速さの平滑化の時定数(秒)。小さいほど速さの変化にすぐ追従する(ぶれにも敏感になる)
    var speedTimeConstant: Double = 0.02
    /// 動き出す前に止まっていなければならない時間(秒)
    var dwellTime: Double = 0.08
    /// フリックの長さの範囲(秒)。短すぎる止まり(空中タップの折り返しの瞬間)では切らない。長すぎる動きは移動とみなす
    var minDuration: Double = 0.1
    var maxDuration: Double = 0.4
    /// これより大きい移動は、フリックではなく「キーの上への移動」とみなす(手の大きさ単位)
    var maxDistance: Double = 0.7
    /// これより移動が小さければタップ(手の大きさ単位)
    var tapDistance: Double = 0.1
    /// タップとフリックの境目のなだらかさ
    var tapSoftness: Double = 0.03
    /// 方向の分布の鋭さ(フォン・ミーゼス分布の κ)。大きいほど、方向の判定が厳しい
    var kappa: Double = 3.0
    /// 始点の位置のばらつき(キーの大きさに対する割合)
    var startSigma: Double = 0.35
    /// 仮名の言語モデルを使う
    var useLanguageModel: Bool = true
    /// 言語モデルの重み
    var lmWeight: Double = 0.5
    /// 機能パッドの割り当て(指 → 動作)
    var functionMapping: [String: FunctionAction] = [
        Finger.thumb.rawValue: .space,
        Finger.index.rawValue: .modifier,
        Finger.middle.rawValue: .backspace,
        Finger.ring.rawValue: .newline,
        Finger.little.rawValue: .nextCandidate,
    ]

    func action(for finger: Finger) -> FunctionAction {
        functionMapping[finger.rawValue] ?? .none
    }

    func isFlickHand(_ chirality: Chirality) -> Bool {
        bothHands || chirality == hand
    }
}

/// フリックパッドの1つのキー(手の座標に置いたもの)
struct FlickKey: Equatable, Identifiable {
    var row: Int
    var column: Int
    var definition: FlickKeyDefinition
    var hand: Chirality
    /// 中心と大きさ(キー配置の座標)
    var center: Vec2
    var size: Vec2

    var id: String { "\(hand.rawValue)-flick-\(row)-\(column)" }
}

/// 切り出したフリック1回分
struct FlickGesture: Equatable, Codable {
    var finger: FingerID
    var startTime: Double
    var endTime: Double
    /// 始点(キー配置の座標)。どのキーかを決める
    var start: Vec2
    /// 移動(手のひらに対する指先の動き、手の座標)。方向を決める
    var displacement: Vec2
    var peakSpeed: Double
}

/// フリックの解読の候補
struct FlickCandidate: Equatable {
    var output: String
    var key: FlickKey
    var direction: FlickDirection
    var probability: Double
    /// log P(キー) + log P(方向)(言語モデルを含まない)
    var logLikelihood: Double
}

struct FlickDecodeResult: Equatable {
    var candidates: [FlickCandidate]
    var keyProbabilities: [String: Double]
    var directionProbabilities: [FlickDirection: Double]
    var best: FlickCandidate? { candidates.first }
}

/// フリックの配置・方向の確率・仮名の解読
enum FlickModel {
    /// フリックパッドのキーを作る。人差し指のホーム位置を「な」(2段目の真ん中)にする
    static func makeKeys(for calibration: HandCalibration, config: FlickConfig) -> [FlickKey] {
        guard let home = calibration.homeTips[.index] else { return [] }
        let pitch = calibration.keyPitch * config.keyScale
        let rowPitch = calibration.rowPitch * config.keyScale
        // 「キーボードの右」は、左手では親指側(+x)、右手では小指側(−x)
        let keyboardRight: Double = calibration.chirality == .left ? 1 : -1
        return FlickLayout.allKeys.map { entry in
            let center = home + Vec2(Double(entry.column - 1) * pitch * keyboardRight,
                                     -Double(entry.row - 1) * rowPitch)
            return FlickKey(row: entry.row, column: entry.column, definition: entry.definition,
                            hand: calibration.chirality, center: center,
                            size: Vec2(pitch * 0.92, rowPitch * 0.92))
        }
    }

    /// 方向の確率(5クラス)。
    /// - タップの確率: 移動が tapDistance より小さいほど高い(ロジスティック関数でなだらかに)
    /// - フリックの方向: フォン・ミーゼス分布(角度版の正規分布)。exp(κ cos(角度 − 方向 − 回転のずれ))
    /// - Parameter rotation: 指ごとの「いつも少し回ってしまう」角度(個人適応。ラジアン)
    static func directionProbabilities(displacement: Vec2, hand: Chirality, config: FlickConfig,
                                       rotation: Double = 0) -> [FlickDirection: Double] {
        let distance = displacement.length
        let tap = 1 / (1 + exp((distance - config.tapDistance) / max(config.tapSoftness, 1e-6)))
        // 画面で見た向き(右 = 0、上 = π/2)。右手では手の座標の x(親指側)が画面の左なので反転する
        let keyboardRight: Double = hand == .left ? 1 : -1
        let angle = atan2(displacement.y, displacement.x * keyboardRight)
        var weights: [FlickDirection: Double] = [:]
        var sum = 0.0
        for direction in FlickDirection.allCases {
            guard let mu = direction.angle else { continue }
            let w = exp(config.kappa * cos(angle - mu - rotation))
            weights[direction] = w
            sum += w
        }
        var result: [FlickDirection: Double] = [.tap: tap]
        for (direction, w) in weights { result[direction] = (1 - tap) * w / sum }
        return result
    }

    /// 始点の位置から、各キーの確率
    static func keyProbabilities(start: Vec2, keys: [FlickKey], config: FlickConfig) -> [String: Double] {
        var logs: [String: Double] = [:]
        for key in keys {
            let cov = Covariance2.diagonal(sigmaX: config.startSigma * key.size.x, sigmaY: config.startSigma * key.size.y)
            logs[key.id] = cov.logDensity(of: start - key.center)
        }
        let maxLog = logs.values.max() ?? 0
        let sum = logs.values.reduce(0) { $0 + exp($1 - maxLog) }
        return logs.mapValues { exp($0 - maxLog) / sum }
    }

    /// 1回のフリックを、仮名の候補(確率の高い順)にする
    /// - Parameters:
    ///   - context: 直前の仮名の並び(言語モデルの文脈)
    ///   - languageModel: 仮名の言語モデル(nil なら使わない)
    static func decode(gesture: FlickGesture, keys: [FlickKey], context: String, config: FlickConfig,
                       rotation: Double = 0, languageModel: ((Character, String) -> Double)?) -> FlickDecodeResult {
        let handKeys = keys.filter { $0.hand == gesture.finger.chirality }
        let keyProbs = keyProbabilities(start: gesture.start, keys: handKeys, config: config)
        let dirProbs = directionProbabilities(displacement: gesture.displacement, hand: gesture.finger.chirality,
                                              config: config, rotation: rotation)
        var scored: [(FlickCandidate, Double)] = []
        for key in handKeys {
            let pk = keyProbs[key.id] ?? 0
            guard pk > 1e-6 else { continue }
            for direction in FlickDirection.allCases {
                guard let output = key.definition.output(for: direction), let pd = dirProbs[direction], pd > 1e-6 else {
                    continue
                }
                let logLikelihood = log(pk) + log(pd)
                var score = logLikelihood
                if config.useLanguageModel, let lm = languageModel {
                    // 「゛」(濁点などの切り替え)は文字ではないので、言語モデルでは平均的な確率として扱う
                    let p = key.definition.isModifier ? 1.0 / Double(FlickLayout.kanaVocabulary.count)
                                                      : lm(Character(output), context)
                    score += config.lmWeight * log(max(p, 1e-300))
                }
                scored.append((FlickCandidate(output: output, key: key, direction: direction, probability: 0,
                                              logLikelihood: logLikelihood), score))
            }
        }
        let maxScore = scored.map(\.1).max() ?? 0
        let sum = scored.reduce(0) { $0 + exp($1.1 - maxScore) }
        let candidates = scored.map { item -> FlickCandidate in
            var c = item.0
            c.probability = exp(item.1 - maxScore) / sum
            return c
        }.sorted { $0.probability > $1.probability }
        return FlickDecodeResult(candidates: candidates, keyProbabilities: keyProbs, directionProbabilities: dirProbs)
    }

    /// 「扇形の広がり」の可視化用: あるキーの 5 方向の、文脈による事前確率(言語モデル^w を正規化したもの)
    static func directionPriors(for key: FlickKey, context: String, config: FlickConfig,
                                languageModel: ((Character, String) -> Double)?) -> [FlickDirection: Double] {
        var weights: [FlickDirection: Double] = [:]
        for direction in FlickDirection.allCases {
            guard let output = key.definition.output(for: direction) else { continue }
            var w = 1.0
            if config.useLanguageModel, let lm = languageModel, !key.definition.isModifier {
                w = pow(max(lm(Character(output), context), 1e-12), config.lmWeight)
            }
            weights[direction] = w
        }
        let sum = weights.values.reduce(0, +)
        return weights.mapValues { $0 / max(sum, 1e-12) }
    }
}

/// エアフリック(方式A)のジェスチャーの切り出し。
///
/// ```
///  [止まっている] ──(dwellTime 以上止まった後、startSpeed を超えた)──▶ [動いている]
///        ▲                                                          │
///        └────────────── endSpeed を下回った = 1回のフリック ◀──────┘
/// ```
/// 始点 = 動き出す直前に止まっていた位置。移動 = 止まった位置 − 始点(手のひらに対する指先の位置で測る)。
final class FlickSegmenter {
    var config = FlickConfig()

    private enum Phase {
        /// since: 止まり始めた時刻、bandSince: 「止まりと動き出しの間の速さ」になった時刻
        case still(since: Double?, bandSince: Double?)
        /// slowSince: 止まりの速さを下回り始めた時刻(空中タップの折り返しの一瞬で切らないため)
        case moving(startTime: Double, start: Vec2, startRel: Vec2, peak: Double, slowSince: Double?)
    }

    /// 中間の速さが、これより長く続いたら「ゆっくりした移動」とみなし、止まっていた記録を捨てる(秒)
    private let maxBandDuration = 0.12

    private struct State {
        /// 指先の位置(キー配置の座標)と、手のひらに対する位置(手の座標)のぶれ除去
        var positionFilter: OneEuroFilter2
        var relFilter: OneEuroFilter2
        var lastTime: Double
        var rel: Vec2
        var speed: Double
        var anchor: Vec2
        var anchorRel: Vec2
        var phase: Phase
        /// 方式B 用: 最近の位置(時刻, キー配置の座標, 手の座標, 速さ)
        var history: [(t: Double, position: Vec2, rel: Vec2, speed: Double)] = []
        /// 方式B 用: この指に割り当てられた接触(音)の時刻
        var contact: Double?
    }

    private var states: [FingerID: State] = [:]
    /// 方式B「接触フリック」: 音のオンセットで始まりを決める(速さでは始めない)
    var contactMode = false
    /// まだどの指にも割り当てていない接触(音)の時刻
    private var pendingContacts: [Double] = []

    /// 方式B: 接触(音のオンセット)を知らせる
    func noteContact(at time: Double) {
        guard contactMode else { return }
        pendingContacts.append(time)
    }

    /// 接触を、その直後にいちばん速く動いた指に割り当てる(両手ともフリックパッドのとき用)。
    /// 直後の動きを見るため、接触の 0.12 秒後のフレームまで待ってから決める(始点は履歴から取るので遅れない)
    private func assignContacts(now: Double) {
        pendingContacts.removeAll { $0 < now - 0.4 }
        var remaining: [Double] = []
        for contact in pendingContacts {
            guard now >= contact + 0.12 else { remaining.append(contact); continue }
            let best = states.max { a, b in
                Self.motion(a.value.history, around: contact) < Self.motion(b.value.history, around: contact)
            }
            // 本物の接触は「キーの上で一瞬止まる → 下ろす」の後に来る。キーへの移動の途中で鳴った音
            // (まわりの物音など)は、直前に止まっていないので捨てる
            let wasStill = best.map { Self.wasStill($0.value.history, before: contact, below: config.endSpeed) } ?? false
            if let best, wasStill, Self.motion(best.value.history, around: contact) >= config.contactMinSpeed {
                states[best.key]?.contact = contact
            }
        }
        pendingContacts = remaining
    }

    private static func wasStill(_ history: [(t: Double, position: Vec2, rel: Vec2, speed: Double)],
                                 before time: Double, below speed: Double) -> Bool {
        history.contains { $0.t >= time - 0.2 && $0.t <= time - 0.03 && $0.speed < speed }
    }

    private static func motion(_ history: [(t: Double, position: Vec2, rel: Vec2, speed: Double)],
                               around time: Double) -> Double {
        history.filter { $0.t >= time - 0.05 && $0.t <= time + 0.12 }.map(\.speed).max() ?? -1
    }
    /// 今まさに動いている指の、始点と今の移動(画面表示用)
    private(set) var active: [FingerID: (start: Vec2, displacement: Vec2)] = [:]

    func reset() {
        states.removeAll()
        active.removeAll()
        pendingContacts.removeAll()
    }

    /// 1フレーム分を処理する
    /// - Parameters:
    ///   - finger: フリックに使う指
    ///   - position: 指先の位置(キー配置の座標)
    ///   - rel: 手のひらに対する指先の位置(手の座標)
    func process(finger: FingerID, position: Vec2?, rel: Vec2?, time: Double) -> FlickGesture? {
        guard let rawPosition = position, let rawRel = rel else {
            states[finger] = nil
            active[finger] = nil
            return nil
        }
        guard var state = states[finger], time > state.lastTime, time - state.lastTime < 0.2 else {
            var positionFilter = OneEuroFilter2(minCutoff: config.filterMinCutoff, beta: config.filterBeta)
            var relFilter = positionFilter
            _ = positionFilter.filter(rawPosition, time: time)
            _ = relFilter.filter(rawRel, time: time)
            states[finger] = State(positionFilter: positionFilter, relFilter: relFilter, lastTime: time, rel: rawRel,
                                   speed: 0, anchor: rawPosition, anchorRel: rawRel,
                                   phase: .still(since: time, bandSince: nil))
            return nil
        }
        // ぶれ除去(オフなら、そのままの値)
        var position = rawPosition
        var rel = rawRel
        if config.useJitterFilter {
            state.positionFilter.minCutoff = config.filterMinCutoff
            state.positionFilter.beta = config.filterBeta
            state.relFilter.minCutoff = config.filterMinCutoff
            state.relFilter.beta = config.filterBeta
            position = state.positionFilter.filter(rawPosition, time: time)
            rel = state.relFilter.filter(rawRel, time: time)
        }
        let dt = time - state.lastTime
        let raw = (rel - state.rel).length / dt
        // 速さの平滑化は「時間」で決める(1フレームごとの係数で決めると、30fps では 60fps の倍ほど遅れて、
        // 短いフリックの山がつぶれて見逃す)。時定数 speedTimeConstant 秒の指数移動平均
        let alpha = 1 - exp(-dt / max(config.speedTimeConstant, 1e-3))
        state.speed = state.speed + (raw - state.speed) * alpha
        state.rel = rel
        state.lastTime = time
        state.history.append((time, position, rel, state.speed))
        state.history.removeAll { $0.t < time - 0.5 }

        var gesture: FlickGesture?
        if contactMode {
            states[finger] = state
            assignContacts(now: time)
            state = states[finger] ?? state
            gesture = processContact(finger: finger, state: &state, position: position, rel: rel, time: time)
            states[finger] = state
            return gesture
        }
        switch state.phase {
        case .still(let since, let bandSince):
            if state.speed < config.endSpeed {
                // 止まっている間は、始点を今の位置に更新し続ける
                state.anchor = position
                state.anchorRel = rel
                state.phase = .still(since: since ?? time, bandSince: nil)
            } else if state.speed > config.startSpeed {
                // 速く動き出した: その前に dwellTime 以上止まっていたらフリックの始まり
                let moveStart = bandSince ?? (time - dt)
                if let since, moveStart - since >= config.dwellTime {
                    state.phase = .moving(startTime: moveStart, start: state.anchor, startRel: state.anchorRel,
                                          peak: state.speed, slowSince: nil)
                } else {
                    state.phase = .still(since: nil, bandSince: nil)
                }
            } else {
                // 止まりと動き出しの間の速さ: 動き出しの途中かもしれないので少しだけ待つ。
                // 長く続くなら、ゆっくりした移動(キーの上への移動)なので止まっていた記録を捨てる
                let band = bandSince ?? time
                state.phase = time - band > maxBandDuration ? .still(since: nil, bandSince: nil)
                                                            : .still(since: since, bandSince: band)
            }
        case .moving(let startTime, let start, let startRel, let peak, let slowSince):
            active[finger] = (start, rel - startRel)
            let slow = state.speed < config.endSpeed ? (slowSince ?? time) : nil
            if let slow, time - slow >= config.endHold - 1e-9, time - startTime >= config.minDuration {
                let displacement = rel - startRel
                // 大きすぎる移動は「キーの上への移動」なので、フリックにしない
                if displacement.length <= config.maxDistance {
                    gesture = FlickGesture(finger: finger, startTime: startTime, endTime: time, start: start,
                                           displacement: displacement, peakSpeed: peak)
                }
                state.phase = .still(since: time, bandSince: nil)
                state.anchor = position
                state.anchorRel = rel
                active[finger] = nil
            } else if time - startTime > config.maxDuration {
                state.phase = .still(since: nil, bandSince: nil)
                active[finger] = nil
            } else {
                state.phase = .moving(startTime: startTime, start: start, startRel: startRel,
                                      peak: max(peak, state.speed), slowSince: slow)
            }
        }
        states[finger] = state
        return gesture
    }

    /// 方式B: 接触(音)から始まり、止まるか contactWindow 秒たったら終わる
    private func processContact(finger: FingerID, state: inout State, position: Vec2, rel: Vec2,
                                time: Double) -> FlickGesture? {
        switch state.phase {
        case .still:
            guard let contact = state.contact, contact <= time else { return nil }
            state.contact = nil
            // 接触の時刻にいちばん近い位置を始点にする(音はカメラより少し遅れて届くことがある)
            let sample = state.history.min { abs($0.t - contact) < abs($1.t - contact) }
            state.phase = .moving(startTime: contact, start: sample?.position ?? position, startRel: sample?.rel ?? rel,
                                  peak: state.speed, slowSince: nil)
            return nil
        case .moving(let startTime, let start, let startRel, let peak, let slowSince):
            active[finger] = (start, rel - startRel)
            let slow = state.speed < config.endSpeed ? (slowSince ?? time) : nil
            let stopped = slow.map { time - $0 >= config.endHold - 1e-9 } ?? false
            if (stopped && time - startTime >= config.minDuration) || time - startTime >= config.contactWindow {
                state.phase = .still(since: time, bandSince: nil)
                state.contact = nil
                active[finger] = nil
                let displacement = rel - startRel
                guard displacement.length <= config.maxDistance else { return nil }
                return FlickGesture(finger: finger, startTime: startTime, endTime: time, start: start,
                                    displacement: displacement, peakSpeed: max(peak, state.speed))
            }
            state.phase = .moving(startTime: startTime, start: start, startRel: startRel,
                                  peak: max(peak, state.speed), slowSince: slow)
            return nil
        }
    }
}

/// 仮名の並び(句読点や空白で区切られるまでのひとまとまり)を、ビームサーチで決め直す
final class KanaBeamDecoder {
    var beamWidth = 8
    var candidatesPerStep = 6
    var languageModel: ((Character, String) -> Double)?
    var lmWeight: Double = 0.5

    /// - Parameters:
    ///   - steps: フリックごとの候補(logLikelihood を使う)
    ///   - context: 並びの直前までの文字列
    /// - Returns: 上位の候補の文字列(スコアの高い順)
    func decode(steps: [[FlickCandidate]], context: String) -> [String] {
        var beams: [(text: String, score: Double)] = [("", 0)]
        for step in steps {
            let options = step.sorted { $0.probability > $1.probability }.prefix(candidatesPerStep)
            var merged: [String: Double] = [:]
            for beam in beams {
                for option in options {
                    var text = beam.text
                    var score = beam.score + option.logLikelihood
                    if option.key.definition.isModifier {
                        // 直前の仮名を切り替える(切り替えられなければ何もしない)
                        if let last = text.last, let next = KanaModifier.cycle(last) {
                            text = String(text.dropLast()) + String(next)
                            if let lm = languageModel {
                                score += lmWeight * log(max(lm(next, context + String(text.dropLast())), 1e-300))
                            }
                        }
                    } else {
                        if let lm = languageModel, let c = option.output.first {
                            score += lmWeight * log(max(lm(c, context + text), 1e-300))
                        }
                        text += option.output
                    }
                    if score > (merged[text] ?? -Double.infinity) { merged[text] = score }
                }
            }
            var list: [(text: String, score: Double)] = []
            for (text, score) in merged { list.append((text: text, score: score)) }
            list.sort { a, b in
                if a.score != b.score { return a.score > b.score }
                return a.text < b.text
            }
            beams = Array(list.prefix(beamWidth))
        }
        return beams.map(\.text)
    }
}
