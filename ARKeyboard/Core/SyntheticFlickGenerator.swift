import Foundation

/// 合成のフリック入力の記録を作る(評価ツールの動作確認と、QWERTY との比較の見通しを立てるため)。
///
/// ⚠️ 人工的に作った手の動きです。実際の人のフリックとは違うので、出た数値を「性能」として扱わないこと。
///
/// 1文字ごとの動き(フリックパッドの手の人差し指):
///   1. キーの上へ「ゆっくり」移動する(平均 1 手/秒 程度。フリックと区別できる速さ)
///   2. 少し止まる(フリックの始まりの目印)
///   3. 方向へ素早く動かして止める(フリック)。あ段は、空中で指を下ろして戻す(空中タップ)
///   4. 濁点・小文字の文字なら、もう一方の手の人差し指(機能パッドの「゛゜小」)をタップする
/// 方向には、毎回のばらつき(角度の雑音)と、その人の癖(いつも同じ向きに回る = 回転のずれ)を入れられます。
struct SyntheticFlickConfig: Codable {
    var targets: [String]
    var seed: UInt64 = 1
    var fps: Double = 30
    /// 始点の狙いのずれ(キーの大きさに対する標準偏差)
    var aimNoise: Double = 0.2
    /// 方向の毎回のばらつき(度)
    var angleNoiseDegrees: Double = 12
    /// その人の癖: いつも同じ向きに回る角度(度。正 = 反時計回り)
    var rotationBiasDegrees: Double = 0
    /// フリックの長さ(手の大きさ単位)の平均とばらつき
    var flickLength: Double = 0.3
    var flickLengthNoise: Double = 0.05
    /// フリックにかける時間(秒)
    var flickDuration: Double = 0.12
    /// キーの上へ移動する速さ(手/秒、平均)
    var repositionSpeed: Double = 1.0
    /// フリックの前に止まる時間(秒)
    var dwell: Double = 0.12
    /// 関節点の震え(手の大きさに対する標準偏差、フレームごと)
    var jointJitter: Double = 0.004
    /// 機能パッドのタップの音が取れない割合
    var audioMissRate: Double = 0.05
    /// フリックの始まりにも音を出す(方式B「接触フリック」の評価用。面をこすって始めるとみなす)
    var contactAudio: Bool = false
    /// タップと関係ない音(雑音)の頻度(1秒あたり)
    var falseOnsetRate: Double = 0.3
    var frameDropRate: Double = 0.01
}

enum SyntheticFlickGenerator {
    /// 指先の動きの区間(手の座標での、ホームからのずれ)
    private enum Segment {
        /// from から to へなめらかに動く
        case move(t0: Double, t1: Double, from: Vec2, to: Vec2)
        /// 空中タップ: at の位置で、指を手首の方向へ depth だけ下ろして戻す
        case dip(t0: Double, t1: Double, at: Vec2, depth: Double)
    }

    static func generate(_ config: SyntheticFlickConfig) -> Recording {
        var rng = SplitMix64(seed: config.seed)
        let baseLeft = SyntheticHand(chirality: .left, origin: Vec2(200, 1000))
        let baseRight = SyntheticHand(chirality: .right, origin: Vec2(520, 1000))
        let calRight = Calibrator.makeCalibration(from: baseRight.observation(), chirality: .right, config: .init())!

        var settings = KeyboardSettings.defaults(for: .knee)
        settings.inputMode = .flick
        settings.features.audioOnset = true
        let flickConfig = settings.flick
        let keys = FlickModel.makeKeys(for: calRight, config: flickConfig)
        let home = calRight.homeTips[.index] ?? SyntheticHand.homeLocal[.indexTip]!
        let task = RecordingTask(kind: .kana, targets: config.targets)
        var recording = Recording(createdAt: Date(timeIntervalSince1970: 0), device: "synthetic-flick",
                                  task: task, settings: settings, calibration: nil, deskPlane: nil)

        func ease(_ x: Double) -> Double {
            let t = min(max(x, 0), 1)
            return t * t * (3 - 2 * t)
        }

        // 1. 動きの予定を作る
        var segments: [Segment] = []
        var modifierTaps: [Double] = []   // 機能パッドの指が面に触れる時刻
        var truths: [Double] = []
        var current = Vec2.zero           // 人差し指の、ホームからのずれ
        var t = 3.0                       // 最初の 3 秒は自動キャリブレーション用に静止
        let tapDepth = 0.12
        let modifierFinger: Finger = Finger.allCases.first { flickConfig.action(for: $0) == .modifier } ?? .index
        for (i, target) in config.targets.enumerated() {
            recording.prompts.append(RecordedPrompt(index: i, target: target, shownAt: t))
            let base = KanaModifier.base(of: target) ?? target
            guard let position = FlickLayout.position(of: base),
                  let key = keys.first(where: { $0.row == position.row && $0.column == position.column }) else {
                t += 0.5
                continue
            }
            // 濁点などを付けるのに必要な「゛゜小」の回数
            var modifierCount = 0
            if base != target, var c = base.first {
                while String(c) != target, let next = KanaModifier.cycle(c), modifierCount < 3 {
                    c = next
                    modifierCount += 1
                }
            }
            // 1. キーの上へ移動(始点の狙いのずれ込み)
            let aim = key.center - home + Vec2(rng.nextGaussian() * config.aimNoise * key.size.x,
                                               rng.nextGaussian() * config.aimNoise * key.size.y)
            let reach = max(0.2, current.distance(to: aim) / max(config.repositionSpeed, 0.1) * 1.0)
            segments.append(.move(t0: t, t1: t + reach, from: current, to: aim))
            current = aim
            t += reach + config.dwell
            truths.append(t)
            // 2. フリック(または空中タップ)
            if let mu = position.direction.angle {
                let keyboardRight: Double = -1  // 右手: 画面の右 = 手の座標の −x
                let angle = mu + (config.rotationBiasDegrees + rng.nextGaussian() * config.angleNoiseDegrees) * Double.pi / 180
                let length = max(0.15, config.flickLength + rng.nextGaussian() * config.flickLengthNoise)
                let to = current + Vec2(cos(angle) * length * keyboardRight, sin(angle) * length)
                segments.append(.move(t0: t, t1: t + config.flickDuration, from: current, to: to))
                current = to
                t += config.flickDuration
            } else {
                segments.append(.dip(t0: t, t1: t + 0.14, at: current, depth: 0.15))
                t += 0.14
            }
            t += 0.15
            // 3. 濁点などは機能パッドをタップ
            for _ in 0..<modifierCount {
                modifierTaps.append(t + 0.11)   // 下ろし始めから触れるまで
                t += 0.35
            }
        }
        let end = t + 1.0
        recording.groundTruthTaps = truths

        // 2. フレームを作る
        var frameTime = 0.0
        var segmentIndex = 0
        while frameTime < end {
            defer { frameTime += 1 / config.fps }
            if rng.nextUniform() < config.frameDropRate { continue }
            // 人差し指の位置
            while segmentIndex + 1 < segments.count, Self.start(of: segments[segmentIndex + 1]) <= frameTime {
                segmentIndex += 1
            }
            var offset = Vec2.zero
            if !segments.isEmpty, Self.start(of: segments[segmentIndex]) <= frameTime {
                switch segments[segmentIndex] {
                case let .move(t0, t1, from, to):
                    offset = Vec2.lerp(from, to, ease((frameTime - t0) / (t1 - t0)))
                case let .dip(t0, t1, at, depth):
                    let x = (frameTime - t0) / (t1 - t0)
                    offset = at - Vec2(0, x > 0 && x < 1 ? depth * sin(Double.pi * x) : 0)
                }
            }
            let right = baseRight.moving(.index, by: offset)
            // 機能パッドの手: 打ち始めたら指を浮かせ、「゛゜小」のときだけ下ろして触れる
            var left = baseLeft
            if frameTime >= 3.0 {
                for finger in Finger.allCases { left = left.moving(finger, by: Vec2(0, tapDepth)) }
                for contact in modifierTaps where frameTime > contact - 0.11 && frameTime < contact + 0.19 {
                    let local = frameTime - (contact - 0.11)
                    let down = local < 0.06 ? ease(local / 0.06) : 1
                    let up = local > 0.11 ? ease((local - 0.11) / 0.08) : 0
                    left = left.moving(modifierFinger, by: Vec2(0, -tapDepth * (down - up)))
                }
            }
            var observations: [HandObservation] = []
            for hand in [left, right] {
                var obs = hand.observation()
                for (joint, point) in obs.joints {
                    let amount = config.jointJitter * hand.scale
                    obs.joints[joint]?.position = point.position + Vec2(rng.nextGaussian() * amount,
                                                                         rng.nextGaussian() * amount)
                }
                observations.append(obs)
            }
            recording.frames.append(RecordedFrame(VisionFrame(timestamp: frameTime, imageSize: Vec2(720, 1280),
                                                             hands: observations)))
        }

        // 3. 音(合成のタイピングと同じ作り方)
        let hop = 512.0 / 48_000
        var spikes: [(time: Double, height: Double)] = []
        var contacts = modifierTaps
        if config.contactAudio { contacts += truths }
        for contact in contacts where rng.nextUniform() >= config.audioMissRate {
            spikes.append((contact + rng.nextGaussian() * 0.008, 0.04 + 0.03 * rng.nextUniform()))
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

    private static func start(of segment: Segment) -> Double {
        switch segment {
        case let .move(t0, _, _, _): return t0
        case let .dip(t0, _, _, _): return t0
        }
    }

    /// 文章から目標の仮名の並びを作る(フリックで打てない文字・空白・改行は除く)
    static func targets(from text: String) -> [String] {
        let allowed = Set(FlickLayout.kanaVocabulary)
        return text.filter { allowed.contains($0) }.map(String.init)
    }
}
