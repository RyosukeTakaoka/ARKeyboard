import Foundation

/// 片手分のキャリブレーション結果
struct HandCalibration: Codable, Equatable {
    var chirality: Chirality
    /// キャリブレーションした瞬間の手の座標系(「面に固定」モードではこれを基準にキーを置く)
    var frame: HandFrame
    /// ホームポジションでの各指先の位置(手の座標。x: 親指側+, y: 前+)
    /// 左手なら 人差し指=F, 中指=D, 薬指=S, 小指=A、右手なら 人差し指=J, 中指=K, 薬指=L, 小指=; の位置。
    var homeTips: [Finger: Vec2]
    /// キーの横の間隔(手の座標の単位)。隣り合う指先の間隔の平均から求める。
    var keyPitch: Double
    /// 行(段)の間隔(手の座標の単位)。keyPitch × 奥行きの見え方の補正(foreshortening)。
    var rowPitch: Double
    /// 奥行き方向の縮み具合(1 = 真上から見ている、小さいほど斜めから見ている)
    var foreshortening: Double
}

/// 両手分のキャリブレーション結果
struct CalibrationResult: Codable, Equatable {
    var left: HandCalibration
    var right: HandCalibration
    var createdAt: Date

    func hand(_ chirality: Chirality) -> HandCalibration {
        chirality == .left ? left : right
    }
}

/// 「両手をホームポジションに置いて2秒静止」を検出し、キャリブレーション結果を作るクラス。
///
/// 流れ:
/// 1. start() で開始
/// 2. 毎フレーム process(...) に両手を渡す
/// 3. 両手が見えていて、指先が 2 秒間ほぼ動かなければ、その間の平均位置から結果を作って返す
final class Calibrator {
    /// 進み具合(画面表示に使う)
    enum Phase: Equatable {
        /// キャリブレーションしていない
        case idle
        /// 両手が見えるのを待っている
        case waitingForHands
        /// 静止を計測中(progress: 0〜1)
        case holding(progress: Double)
        /// 完了した
        case finished
    }

    struct Config {
        /// 静止していなければならない時間(秒)
        var requiredDuration: Double = 2.0
        /// 「静止」とみなす指先の移動量の上限(手の大きさ単位。0.08 ≒ 手首〜中指付け根の 8%)
        var stillnessTolerance: Double = 0.08
        /// この信頼度より低い点は使わない
        var minConfidence: Double = 0.3
        /// 人の手の「手のひらの幅 ÷ 手首〜中指付け根の長さ」のおおよその値
        /// (人差し指〜小指の付け根の幅 約7cm ÷ 約9.5cm)。奥行きの縮み具合の推定に使う。
        var typicalPalmWidthRatio: Double = 0.75
    }

    var config = Config()
    private(set) var phase: Phase = .idle
    /// 画面に出す案内メッセージ
    private(set) var message: String = ""

    /// 静止判定中に集めたサンプル(時刻と両手の観測)
    private var samples: [(time: Double, hands: [Chirality: HandObservation])] = []

    /// キャリブレーション中かどうか
    var isActive: Bool {
        switch phase {
        case .waitingForHands, .holding: return true
        case .idle, .finished: return false
        }
    }

    /// キャリブレーションに必須の関節(手首・こぶし・4本の指先)
    static let requiredJoints: [Joint] = [
        .wrist, .indexMCP, .middleMCP, .littleMCP,
        .indexTip, .middleTip, .ringTip, .littleTip,
    ]

    func start() {
        samples.removeAll()
        phase = .waitingForHands
        message = "両手をホームポジション(左: A S D F、右: J K L ;)に置いてください"
    }

    func cancel() {
        samples.removeAll()
        phase = .idle
        message = ""
    }

    /// 1フレーム分を処理します。完了したフレームでだけ結果を返します。
    func process(hands: [Chirality: HandObservation], timestamp: Double) -> CalibrationResult? {
        guard isActive else { return nil }

        // 1. 両手がそろって、必要な点がすべて見えているか
        guard let left = hands[.left], let right = hands[.right],
              hasRequiredJoints(left), hasRequiredJoints(right) else {
            samples.removeAll()
            phase = .waitingForHands
            message = hands.count < 2
                ? "両手をカメラに映してください(今は \(hands.count) 本の手が見えています)"
                : "指先が隠れています。指を開いて、すべての指先が見えるようにしてください"
            return nil
        }
        let current = (time: timestamp, hands: [Chirality.left: left, .right: right])

        // 2. 最初のサンプルから動いていないか(動いたら計測をやり直す)
        if let anchor = samples.first, moved(from: anchor.hands, to: current.hands) {
            samples = [current]
            phase = .holding(progress: 0)
            message = "動きました。そのまま静止してください"
            return nil
        }
        samples.append(current)

        // 3. 2秒たったら、集めたサンプルの平均から結果を作る
        let elapsed = timestamp - (samples.first?.time ?? timestamp)
        phase = .holding(progress: min(1, elapsed / config.requiredDuration))
        message = "そのまま静止してください…"
        guard elapsed >= config.requiredDuration else { return nil }

        guard let leftCalibration = makeCalibration(chirality: .left),
              let rightCalibration = makeCalibration(chirality: .right) else {
            samples.removeAll()
            phase = .waitingForHands
            message = "手の形をうまく測れませんでした。もう一度ホームポジションに置いてください"
            return nil
        }
        phase = .finished
        message = "キャリブレーション完了!"
        samples.removeAll()
        return CalibrationResult(left: leftCalibration, right: rightCalibration, createdAt: Date())
    }

    // MARK: - 内部の計算

    private func hasRequiredJoints(_ hand: HandObservation) -> Bool {
        Self.requiredJoints.allSatisfy { hand.position($0, minConfidence: config.minConfidence) != nil }
    }

    /// 手首と指先のどれかが、許容量以上に動いたか
    private func moved(from old: [Chirality: HandObservation], to new: [Chirality: HandObservation]) -> Bool {
        for chirality in Chirality.allCases {
            guard let oldHand = old[chirality], let newHand = new[chirality],
                  let frame = HandFrame(hand: newHand, minConfidence: config.minConfidence) else {
                return true
            }
            for joint in [Joint.wrist] + Finger.typingFingers.map({ Joint.tip(of: $0) }) {
                guard let a = oldHand.position(joint, minConfidence: config.minConfidence),
                      let b = newHand.position(joint, minConfidence: config.minConfidence) else {
                    return true
                }
                // ピクセルのままだと「カメラとの距離」で基準が変わるので、手の大きさで割る
                if a.distance(to: b) / frame.scale > config.stillnessTolerance {
                    return true
                }
            }
        }
        return false
    }

    /// 集めたサンプルの関節位置を平均して、片手分の結果を作る
    private func makeCalibration(chirality: Chirality) -> HandCalibration? {
        let observations = samples.compactMap { $0.hands[chirality] }
        guard let averaged = Self.average(observations, minConfidence: config.minConfidence) else { return nil }
        return Self.makeCalibration(from: averaged, chirality: chirality, config: config)
    }

    /// 複数フレームの観測を、関節ごとに平均した1つの観測にまとめる(ノイズを減らすため)
    static func average(_ observations: [HandObservation], minConfidence: Double) -> HandObservation? {
        guard !observations.isEmpty else { return nil }
        var joints: [Joint: JointPoint] = [:]
        for joint in Joint.allCases {
            let points = observations.compactMap { $0.joints[joint] }.filter { $0.confidence >= minConfidence }
            guard let mean = Vec2.average(points.map(\.position)) else { continue }
            let confidence = points.map(\.confidence).reduce(0, +) / Double(points.count)
            joints[joint] = JointPoint(position: mean, confidence: confidence)
        }
        return HandObservation(chirality: observations.first?.chirality, joints: joints)
    }

    /// 平均した観測から、手の座標系・ホーム位置・キーの間隔を計算します。
    ///
    /// ## キーの大きさ(ピッチ)と行の間隔の決め方
    /// - **横の間隔(keyPitch)**: ホームポジションでの隣り合う指先(人差し指-中指、中指-薬指、薬指-小指)
    ///   の距離の平均。実際のキーボードも、指の間隔に合わせて約19mm間隔で作られています。
    /// - **行の間隔(rowPitch)**: 実物のキーボードでは縦の間隔も横とほぼ同じ(約19mm)。
    ///   ただしカメラが斜めから見ていると、奥行き方向(前後)が縮んで映ります。
    ///   手の座標は「手首〜中指付け根の長さ(=奥行き方向)」で割って作っているので、
    ///   前後の縮みは自動で打ち消されますが、逆に**横方向が相対的に大きく**見えてしまいます。
    ///   そこで、「手のひらの幅 ÷ 手の長さ」が普通の手(約0.75)よりどれだけ大きく見えるかで
    ///   縮み具合(foreshortening)を推定し、 rowPitch = keyPitch × foreshortening とします。
    static func makeCalibration(from hand: HandObservation, chirality: Chirality, config: Config) -> HandCalibration? {
        guard let frame = HandFrame(hand: hand, minConfidence: config.minConfidence) else { return nil }

        // ホームポジションの指先の位置(手の座標)
        var homeTips: [Finger: Vec2] = [:]
        for finger in Finger.typingFingers {
            guard let tip = hand.position(Joint.tip(of: finger), minConfidence: config.minConfidence) else {
                return nil
            }
            homeTips[finger] = frame.toLocal(tip)
        }

        // 横の間隔 = 隣り合う指先の距離の平均
        let order = Finger.typingFingers  // 人差し指 → 中指 → 薬指 → 小指
        var gaps: [Double] = []
        for i in 0..<(order.count - 1) {
            if let a = homeTips[order[i]], let b = homeTips[order[i + 1]] {
                gaps.append(a.distance(to: b))
            }
        }
        guard !gaps.isEmpty else { return nil }
        // 極端な値(指がくっついている、離れすぎ)は、ありえる範囲に収める
        let keyPitch = min(max(gaps.reduce(0, +) / Double(gaps.count), 0.12), 0.6)

        // 奥行きの縮み具合
        var foreshortening = 1.0
        if let indexMCP = hand.position(.indexMCP, minConfidence: config.minConfidence),
           let littleMCP = hand.position(.littleMCP, minConfidence: config.minConfidence) {
            let observedRatio = indexMCP.distance(to: littleMCP) / frame.scale
            if observedRatio > 0.01 {
                foreshortening = min(max(config.typicalPalmWidthRatio / observedRatio, 0.5), 1.5)
            }
        }
        let rowPitch = keyPitch * foreshortening

        // 親指(スペースキー担当)。見えていなければ、人差し指の手前・内側にあると仮定する
        if let thumbTip = hand.position(.thumbTip, minConfidence: config.minConfidence) {
            homeTips[.thumb] = frame.toLocal(thumbTip)
        } else if let index = homeTips[.index] {
            homeTips[.thumb] = index + Vec2(keyPitch, -rowPitch * 1.5)
        }

        return HandCalibration(chirality: chirality, frame: frame, homeTips: homeTips,
                               keyPitch: keyPitch, rowPitch: rowPitch, foreshortening: foreshortening)
    }
}
