import Foundation

/// 再生した結果のタップ1回分(評価ツールに渡す)
struct ReplayedTap: Codable, Equatable {
    var t: Double
    var finger: FingerID
    /// 入力された文字(却下・範囲外なら nil)
    var output: String?
    var accepted: Bool
    var note: String?
    /// 上位の候補とその確率(デコーダーを使ったとき)
    var candidates: [ReplayedCandidate]?
    /// 音とのずれ(秒)
    var audioOffset: Double?
    /// タップ位置(キー配置の座標)
    var location: Vec2?
    /// タップ推定レベルB の学習用の特徴量(--dump-features のとき)
    var features: [Double]?
}

struct ReplayedCandidate: Codable, Equatable {
    var output: String
    var probability: Double
}

/// 再生の結果
struct ReplayResult: Codable {
    var variant: String
    var frameCount: Int
    var calibrated: Bool
    var taps: [ReplayedTap]
}

/// 記録ファイルを、アプリと同じエンジン(KeyboardEngine)に流し込んで、もう一度判定させる。
///
/// 「機能の組み合わせ(バリアント)」を変えて同じ記録を再生すれば、
/// どの機能がどれだけ効いたかを、同じデータで比べられます(tools/eval/)。
final class Replayer {
    struct Options {
        /// 設定の上書き(JSON の辞書。例: {"features": {"audioOnset": false}})
        var settingsPatch: [String: Any] = [:]
        var variantName = "default"
        /// 関節点に加える人工的なぶれ(手の大きさに対する標準偏差)。ぶれへの強さを比べるため
        var jointNoise: Double = 0
        var noiseSeed: UInt64 = 1
        /// 言語モデルの学習用テキスト
        var englishCorpus: String?
        var romajiCorpus: String?
        /// 記録にキャリブレーションが無ければ、最初の静止部分で自動キャリブレーションする
        var autoCalibrate = true
        /// レベルB の学習用に、タップ候補の特徴量も出力する
        var dumpFeatures = false
        /// レベルB の学習モデル(使うとき)
        var classifier: TapClassifier?
    }

    let recording: Recording
    let options: Options

    init(recording: Recording, options: Options) {
        self.recording = recording
        self.options = options
    }

    /// 設定に上書きを重ねる
    static func applyPatch(_ patch: [String: Any], to settings: KeyboardSettings) -> KeyboardSettings {
        guard !patch.isEmpty,
              let data = try? RecordingIO.encoder().encode(settings),
              let base = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let merged = try? JSONSerialization.data(withJSONObject: TolerantDecoding.merge(base, patch)),
              let result = try? RecordingIO.decoder().decode(KeyboardSettings.self, from: merged) else {
            return settings
        }
        return result
    }

    func run() -> ReplayResult {
        let settings = Self.applyPatch(options.settingsPatch, to: recording.settings)
        let engine = KeyboardEngine(settings: settings)
        engine.setLanguageCorpora(english: options.englishCorpus, romaji: options.romajiCorpus)
        engine.deskPlane = recording.deskPlane
        engine.tapClassifier = options.classifier
        if let calibration = recording.calibration {
            engine.setCalibration(calibration)
        } else if options.autoCalibrate {
            engine.startCalibration()
        }

        var rng = SplitMix64(seed: options.noiseSeed)
        var taps: [ReplayedTap] = []
        var typed = ""

        // すべての出来事を時刻順に並べる(フレーム・音・振動・画面のボタン)
        enum Item {
            case frame(RecordedFrame)
            case audio(time: Double)
            case motion(time: Double)
            case edit(RecordedEvent)
        }
        var items: [(time: Double, order: Int, item: Item)] = []
        for f in recording.frames { items.append((f.t, 0, .frame(f))) }
        // 音は 10ms ごとの特徴の時刻に「そこまで解析が終わった」として届ける
        for a in recording.audioFeatures { items.append((a.time, 1, .audio(time: a.time))) }
        // 振動は 50ms ごとにまとめて届く
        var lastMotion = -Double.infinity
        for m in recording.motionSamples where m.time - lastMotion >= 0.05 {
            items.append((m.time, 1, .motion(time: m.time)))
            lastMotion = m.time
        }
        for e in recording.events where e.kind != .tap { items.append((e.t, 2, .edit(e))) }
        items.sort { $0.time != $1.time ? $0.time < $1.time : $0.order < $1.order }

        var deliveredAudio = 0
        var deliveredMotion = 0
        let audioOnsets = recording.audioOnsets.sorted { $0.time < $1.time }
        let motionOnsets = recording.motionOnsets.sorted { $0.time < $1.time }

        func collect(_ results: [TapResult]) {
            for r in results {
                if let key = r.key { typed += key.output }
                var tap = ReplayedTap(t: r.event.timestamp, finger: r.event.finger, output: r.key?.output,
                                      accepted: r.key != nil, note: r.note,
                                      candidates: r.decode.map { $0.candidates.prefix(3).map {
                                          ReplayedCandidate(output: $0.key.output, probability: $0.probability) } },
                                      audioOffset: r.audioOffset, location: r.touch?.surfaceLocation)
                if options.dumpFeatures { tap.features = r.levelBFeatures }
                taps.append(tap)
            }
        }

        for entry in items {
            engine.context = String(typed.suffix(12)).replacingOccurrences(of: "\n", with: " ")
            switch entry.item {
            case .frame(let recorded):
                var frame = recorded.visionFrame
                if options.jointNoise > 0 { frame = Self.addNoise(to: frame, sigma: options.jointNoise, rng: &rng) }
                collect(engine.process(frame, now: recorded.t).taps)
            case .audio(let time):
                var newOnsets: [OnsetEvent] = []
                while deliveredAudio < audioOnsets.count, audioOnsets[deliveredAudio].time <= time {
                    newOnsets.append(audioOnsets[deliveredAudio])
                    deliveredAudio += 1
                }
                collect(engine.ingestOnsets(newOnsets, source: .audio, coveredUntil: time, now: time))
            case .motion(let time):
                var newOnsets: [OnsetEvent] = []
                while deliveredMotion < motionOnsets.count, motionOnsets[deliveredMotion].time <= time {
                    newOnsets.append(motionOnsets[deliveredMotion])
                    deliveredMotion += 1
                }
                collect(engine.ingestOnsets(newOnsets, source: .motion, coveredUntil: time, now: time))
            case .edit(let event):
                if event.kind == .backspace, !typed.isEmpty { typed.removeLast() }
                if event.kind == .newline { typed += "\n" }
            }
        }
        // 最後に、保留中の候補を確定させる
        if let last = items.last?.time {
            collect(engine.ingestOnsets([], source: .audio, coveredUntil: last + 1, now: last + 1))
        }
        return ReplayResult(variant: options.variantName, frameCount: recording.frames.count,
                            calibrated: engine.calibration != nil, taps: taps)
    }

    /// 関節点に人工的なぶれを加える(手の大きさに比例したガウス雑音)
    static func addNoise(to frame: VisionFrame, sigma: Double, rng: inout SplitMix64) -> VisionFrame {
        var result = frame
        result.hands = frame.hands.map { hand in
            var noisy = hand
            let size = HandFrame(hand: hand, minConfidence: 0.1)?.scale ?? 100
            for (joint, point) in hand.joints {
                let n = Vec2(rng.nextGaussian(), rng.nextGaussian()) * (sigma * size)
                noisy.joints[joint]?.position = point.position + n
            }
            return noisy
        }
        return result
    }
}

/// 再現できる乱数(同じ seed なら毎回同じ値の列)。評価を何度やっても同じ結果になるようにするため
struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    /// 0〜1 の一様乱数
    mutating func nextUniform() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }

    /// 平均 0、標準偏差 1 の正規乱数(ボックス=ミュラー法)
    mutating func nextGaussian() -> Double {
        let u1 = max(nextUniform(), 1e-12), u2 = nextUniform()
        return (-2 * log(u1)).squareRoot() * cos(2 * Double.pi * u2)
    }
}
