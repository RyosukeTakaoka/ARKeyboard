import Foundation

/// 合成の記録データを作る(評価ツールの動作確認用)。
///
/// ⚠️ これは「人工的に作った手の動き」です。実際の人の打鍵とは違うので、
/// これで出た数値を「このキーボードの性能」として扱ってはいけません。
/// 評価ツール(tools/eval/)が正しく動くかを確かめるため、
/// そして「どの機能が、どんな種類の誤りに効くか」の見通しを立てるために使います。
///
/// 1文字ごとの動き:
///   1. 担当の指を浮かせたまま、狙ったキー(+ 狙いのずれ)の上へ移動する
///      (ここで手首方向に速く動くことがある=カメラだけだと誤検出の元)
///   2. 指を手首の方向へ素早く下ろして止める(=タップ。触れた位置が狙った位置。このとき音のオンセットが出る。
///      たまに音が取れない)
///   3. 指を上げて、ホームポジションの上に戻す
/// ほかに、関節点の細かい震え、ときどきのフレーム落ち、タップと関係ない音(雑音)も入れます。
struct SyntheticTypingConfig: Codable {
    var targets: [String]
    var seed: UInt64 = 1
    var fps: Double = 30
    /// 1文字あたりの時間(秒)。1文字の動き(移動 0.2 + 待ち 0.05 + 下ろす 0.06 + 止まる 0.05 + 上げる 0.08
    /// + 戻る 0.12 = 0.56 秒)より長くすること
    var interval: Double = 0.6
    /// 狙いのずれ(キー間隔に対する標準偏差)
    var aimNoise: Double = 0.25
    /// 関節点の震え(手の大きさに対する標準偏差、フレームごと)
    var jointJitter: Double = 0.004
    /// 指を下ろす深さ(手の大きさ単位)と時間(秒)
    var tapDepth: Double = 0.12
    var tapDuration: Double = 0.06
    /// キーへ移動する時間(秒)
    var reachDuration: Double = 0.2
    /// 音が取れないタップの割合
    var audioMissRate: Double = 0.05
    /// 音の遅れのばらつき(秒)
    var audioJitter: Double = 0.008
    /// タップと関係ない音(雑音)の頻度(1秒あたり)
    var falseOnsetRate: Double = 0.3
    /// フレーム落ちの割合
    var frameDropRate: Double = 0.01
    /// 指ごとの押し癖(いつも同じ方向にずれる大きさ。キー間隔に対する割合)。個人適応の効果を見るため
    var fingerBias: Double = 0
    var mode: KeyboardMode = .knee
}

enum SyntheticRecordingGenerator {
    static func generate(_ config: SyntheticTypingConfig) -> Recording {
        var rng = SplitMix64(seed: config.seed)
        let baseLeft = SyntheticHand(chirality: .left, origin: Vec2(200, 1000))
        let baseRight = SyntheticHand(chirality: .right, origin: Vec2(520, 1000))
        let calLeft = Calibrator.makeCalibration(from: baseLeft.observation(), chirality: .left, config: .init())!
        let calRight = Calibrator.makeCalibration(from: baseRight.observation(), chirality: .right, config: .init())!
        let keys = KeyLayout.makeKeys(for: calLeft, keyScale: 1) + KeyLayout.makeKeys(for: calRight, keyScale: 1)

        var settings = KeyboardSettings.defaults(for: config.mode)
        settings.features.audioOnset = true
        let task = RecordingTask(kind: .keys, targets: config.targets)
        var recording = Recording(createdAt: Date(timeIntervalSince1970: 0), device: "synthetic",
                                  task: task, settings: settings, calibration: nil, deskPlane: nil)

        // 指ごとの押し癖(方向はランダム、大きさは fingerBias)
        var biases: [FingerID: Vec2] = [:]
        for finger in FingerID.all {
            let angle = rng.nextUniform() * 2 * Double.pi
            biases[finger] = Vec2(cos(angle), sin(angle)) * config.fingerBias
        }

        // 各文字の動きの予定(どの指を、いつ、どこへ)
        struct Stroke { var finger: FingerID; var start: Double; var aim: Vec2; var contact: Double }
        let typingStart = 3.0  // 最初の 3 秒は、自動キャリブレーション用に静止
        var strokes: [Stroke] = []
        for (i, target) in config.targets.enumerated() {
            let start = typingStart + Double(i) * config.interval
            recording.prompts.append(RecordedPrompt(index: i, target: target, shownAt: start))
            let key: Key? = target == " "
                ? keys.first { $0.isSpace && $0.hand == .right }
                : keys.first { $0.output == target && !$0.isSpace }
            guard let key else { continue }
            let cal = key.hand == .left ? calLeft : calRight
            let bias = biases[FingerID(chirality: key.hand, finger: key.finger)] ?? .zero
            let aimNoise = Vec2((rng.nextGaussian() * config.aimNoise + bias.x) * cal.keyPitch,
                                (rng.nextGaussian() * config.aimNoise + bias.y) * cal.rowPitch)
            let contact = start + config.reachDuration + 0.05 + config.tapDuration
            strokes.append(Stroke(finger: FingerID(chirality: key.hand, finger: key.finger), start: start,
                                  aim: key.center + aimNoise, contact: contact))
        }
        let end = typingStart + Double(config.targets.count) * config.interval + 1.0
        recording.groundTruthTaps = strokes.map(\.contact)

        /// なめらかな 0→1(動き始めと終わりがゆっくり)
        func ease(_ x: Double) -> Double {
            let t = min(max(x, 0), 1)
            return t * t * (3 - 2 * t)
        }

        // フレームを作る
        var t = 0.0
        while t < end {
            defer { t += 1 / config.fps }
            if rng.nextUniform() < config.frameDropRate { continue }
            var hands = [Chirality.left: baseLeft, .right: baseRight]
            // 打ち始めたら、打っていない指も「少し浮かせた位置」にある(キャリブレーション中だけ面に触れている)
            if t >= typingStart {
                for chirality in Chirality.allCases {
                    guard var hand = hands[chirality] else { continue }
                    for finger in Finger.allCases {
                        hand = hand.moving(finger, by: Vec2(0, config.tapDepth))
                    }
                    hands[chirality] = hand
                }
            }
            for stroke in strokes where t >= stroke.start && t < stroke.start + config.interval {
                guard var hand = hands[stroke.finger.chirality] else { continue }
                let home = SyntheticHand.homeLocal[Joint.tip(of: stroke.finger.finger)]!
                // 指を浮かせた状態は、触れる位置より「前(手首から離れる向き)」に見える
                // (上から撮ると、指を下ろす動きは手首の方向への動きとして映るため)
                let hover = Vec2(0, config.tapDepth)
                let rest = home + hover
                let local = t - stroke.start
                let reachEnd = config.reachDuration
                let tapStart = reachEnd + 0.05
                let tapEnd = tapStart + config.tapDuration
                let liftEnd = tapEnd + 0.05 + 0.08
                // 1. 浮かせたままキーの上へ移動 2. 下ろして触れる(ここが狙った位置) 3. 上げる 4. ホームへ戻る
                var position = Vec2.lerp(rest, stroke.aim + hover, ease(local / reachEnd))
                if local >= tapStart {
                    let down = local < tapEnd ? ease((local - tapStart) / config.tapDuration) : 1
                    let up = local > tapEnd + 0.05 ? ease((local - tapEnd - 0.05) / 0.08) : 0
                    position.y -= config.tapDepth * (down - up)
                }
                if local >= liftEnd {
                    position = Vec2.lerp(stroke.aim + hover, rest, ease((local - liftEnd) / 0.12))
                }
                // 打ち始め以降は、すでに全部の指が hover だけ動かしてあるので、その分を引く
                let delta = position - rest
                hand = hand.moving(stroke.finger.finger, by: delta)
                hands[stroke.finger.chirality] = hand
            }
            // 関節点の震え
            var observations: [HandObservation] = []
            for chirality in Chirality.allCases {
                guard let hand = hands[chirality] else { continue }
                var obs = hand.observation()
                for (joint, point) in obs.joints {
                    let amount = config.jointJitter * hand.scale
                    let nx = rng.nextGaussian() * amount
                    let ny = rng.nextGaussian() * amount
                    obs.joints[joint]?.position = point.position + Vec2(nx, ny)
                }
                observations.append(obs)
            }
            recording.frames.append(RecordedFrame(VisionFrame(timestamp: t, imageSize: Vec2(720, 1280),
                                                             hands: observations)))
        }

        // 音: 10.7ms ごとの flux。タップの接触の時刻と、ランダムな雑音で山を作り、アプリと同じ検出器にかける
        let hop = 512.0 / 48_000
        var spikes: [(time: Double, height: Double)] = []
        for stroke in strokes where rng.nextUniform() >= config.audioMissRate {
            spikes.append((stroke.contact + rng.nextGaussian() * config.audioJitter, 0.04 + 0.03 * rng.nextUniform()))
        }
        var noiseTime = 0.0
        while noiseTime < end {
            noiseTime += -log(max(rng.nextUniform(), 1e-9)) / max(config.falseOnsetRate, 1e-9)
            spikes.append((noiseTime, 0.02 + 0.03 * rng.nextUniform()))
        }
        let detector = OnsetDetector(source: .audio, config: settings.audioOnset)
        var time = 0.0
        while time < end {
            var flux = 0.002 + 0.001 * rng.nextUniform()
            for spike in spikes where abs(spike.time - time) < hop / 2 { flux += spike.height }
            if let onset = detector.process(value: flux, time: time) { recording.audioOnsets.append(onset) }
            recording.audioFeatures.append(AudioFeature(time: time, rms: flux, flux: flux, threshold: detector.lastThreshold))
            time += hop
        }
        return recording
    }

    /// 文字列から目標の並びを作る
    static func targets(from text: String) -> [String] {
        CharNGramModel.normalize(text).map(String.init)
    }
}
