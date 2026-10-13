import Foundation

/// 記録モードで保存するデータ(1回の記録 = 1ファイルの JSON)。
///
/// ## 何を保存するか(プライバシーとデータ量のため、映像そのものは保存しない)
/// - フレームごとの手の関節座標(21点 × [x, y, 信頼度])と時刻
/// - 音の特徴(10ms ごとの音量と flux)とオンセット、加速度とそのオンセット
/// - 画面に出した目標(どの文字を打ってほしかったか)と、実際に起きた入力イベント
/// - 記録したときの設定・キャリブレーション・机の四隅
///
/// これを tools/eval/(Mac で実行)で読み込み、アルゴリズムの組み合わせを変えて再生・評価します。
struct Recording: Codable {
    static let formatName = "arkeyboard-recording"
    static let currentVersion = 1

    var format = Recording.formatName
    var version = Recording.currentVersion
    var createdAt: Date
    /// 端末の機種名(例: iPhone15,2)
    var device: String
    var task: RecordingTask
    var settings: KeyboardSettings
    var calibration: CalibrationResult?
    var deskPlane: DeskPlane?

    var frames: [RecordedFrame] = []
    var audioFeatures: [AudioFeature] = []
    var audioOnsets: [OnsetEvent] = []
    var motionSamples: [MotionSample] = []
    var motionOnsets: [OnsetEvent] = []
    var prompts: [RecordedPrompt] = []
    var events: [RecordedEvent] = []
    /// 本当に面に触れた時刻(合成データのときだけ分かる。実際の記録では nil)
    var groundTruthTaps: [Double]? = nil
}

/// 記録の課題
struct RecordingTask: Codable, Equatable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        /// 1文字ずつランダムなキー
        case keys
        /// 短いフレーズ
        case phrases
        /// 仮名(フリック入力用)
        case kana

        var id: String { rawValue }

        var japaneseName: String {
            switch self {
            case .keys: return "1文字ずつ"
            case .phrases: return "フレーズ"
            case .kana: return "仮名(フリック)"
            }
        }
    }

    var kind: Kind
    /// 目標の文字の並び(全体)
    var targets: [String]
}

/// 1フレーム分の手(映像は保存しない)
struct RecordedFrame: Codable, Equatable {
    /// 撮影時刻(秒)
    var t: Double
    /// 画像の幅と高さ
    var w: Double
    var h: Double
    var hands: [RecordedHand]
}

/// 1つの手の関節。j は Joint.allCases の順に [x, y, 信頼度] を並べた 63 個の数(見えない関節は信頼度 0)
struct RecordedHand: Codable, Equatable {
    /// Vision の左右判定("left" / "right" / nil)
    var c: Chirality?
    var j: [Double]

    init(_ hand: HandObservation) {
        c = hand.chirality
        var values: [Double] = []
        values.reserveCapacity(Joint.allCases.count * 3)
        for joint in Joint.allCases {
            if let p = hand.joints[joint] {
                // 小数第2位までに丸めてファイルを小さくする(0.01 ピクセルの精度で十分)
                values += [Self.round(p.position.x), Self.round(p.position.y), Self.round(p.confidence, digits: 3)]
            } else {
                values += [0, 0, 0]
            }
        }
        j = values
    }

    /// HandObservation に戻す(再生用)
    var observation: HandObservation {
        var joints: [Joint: JointPoint] = [:]
        for (i, joint) in Joint.allCases.enumerated() where i * 3 + 2 < j.count {
            let confidence = j[i * 3 + 2]
            guard confidence > 0 else { continue }
            joints[joint] = JointPoint(position: Vec2(j[i * 3], j[i * 3 + 1]), confidence: confidence)
        }
        return HandObservation(chirality: c, joints: joints)
    }

    private static func round(_ v: Double, digits: Double = 2) -> Double {
        let scale = pow(10, digits)
        return (v * scale).rounded() / scale
    }
}

extension RecordedFrame {
    init(_ frame: VisionFrame) {
        t = frame.timestamp
        w = frame.imageSize.x
        h = frame.imageSize.y
        hands = frame.hands.map(RecordedHand.init)
    }

    var visionFrame: VisionFrame {
        VisionFrame(timestamp: t, imageSize: Vec2(w, h), hands: hands.map(\.observation))
    }
}

/// 画面に出した目標
struct RecordedPrompt: Codable, Equatable {
    var index: Int
    /// 打ってほしい文字(スペースは " ")
    var target: String
    /// 表示した時刻(秒)
    var shownAt: Double
}

/// 実際に起きた入力イベント
struct RecordedEvent: Codable, Equatable {
    enum Kind: String, Codable {
        /// タップ(採用・却下の両方)
        case tap
        /// 画面の削除ボタン
        case backspace
        /// 画面の改行ボタン
        case newline
        /// フリック(フリックモード)
        case flick
    }

    var kind: Kind
    var t: Double
    /// 入力された文字(却下・範囲外なら nil)
    var output: String?
    var finger: FingerID?
    var accepted: Bool
    var note: String?
    var audioOffset: Double?
    /// キー配置の座標でのタップ位置
    var location: Vec2?
    /// その時点で表示していた目標の番号
    var promptIndex: Int?
    /// フリックの始点(キー配置の座標)と移動(手の座標)、方向(FlickDirection の番号)
    var flickStart: Vec2? = nil
    var flickDisplacement: Vec2? = nil
    var flickDirection: Int? = nil
}

/// 記録の進行(目標の表示と、入力に合わせた次の目標への進行)
final class RecordingSession {
    private(set) var recording: Recording
    private(set) var promptIndex = 0

    init(task: RecordingTask, settings: KeyboardSettings, calibration: CalibrationResult?,
         deskPlane: DeskPlane?, device: String, startTime: Double) {
        recording = Recording(createdAt: Date(), device: device, task: task, settings: settings,
                              calibration: calibration, deskPlane: deskPlane)
        if let first = task.targets.first {
            recording.prompts.append(RecordedPrompt(index: 0, target: first, shownAt: startTime))
        }
    }

    /// 今の目標(終わっていれば nil)
    var currentTarget: String? {
        promptIndex < recording.task.targets.count ? recording.task.targets[promptIndex] : nil
    }

    var isFinished: Bool { currentTarget == nil }

    var progressText: String {
        "\(min(promptIndex + 1, recording.task.targets.count)) / \(recording.task.targets.count)"
    }

    func addFrame(_ frame: VisionFrame) {
        recording.frames.append(RecordedFrame(frame))
    }

    func addAudio(features: [AudioFeature], onsets: [OnsetEvent]) {
        recording.audioFeatures += features
        recording.audioOnsets += onsets
    }

    func addMotion(samples: [MotionSample], onsets: [OnsetEvent]) {
        recording.motionSamples += samples
        recording.motionOnsets += onsets
    }

    /// タップの結果を記録する。文字が入力されたら(正解・不正解にかかわらず)次の目標へ進む
    func addTap(_ result: TapResult, at time: Double) {
        recording.events.append(RecordedEvent(kind: .tap, t: result.event.timestamp, output: result.key?.output,
                                              finger: result.event.finger, accepted: result.key != nil,
                                              note: result.note, audioOffset: result.audioOffset,
                                              location: result.touch?.surfaceLocation, promptIndex: promptIndex))
        if result.key != nil {
            advance(at: time)
        }
    }

    /// フリックの結果を記録する。仮名が入力されたら次の目標へ進む
    func addFlick(_ result: FlickResult, at time: Double) {
        var event = RecordedEvent(kind: .flick, t: result.gesture.endTime, output: result.output,
                                  finger: result.gesture.finger, accepted: result.output != nil, note: nil,
                                  audioOffset: nil, location: result.gesture.start, promptIndex: promptIndex)
        event.flickStart = result.gesture.start
        event.flickDisplacement = result.gesture.displacement
        event.flickDirection = result.decode.best?.direction.rawValue
        recording.events.append(event)
        if result.output != nil { advance(at: time) }
    }

    func addEdit(_ kind: RecordedEvent.Kind, at time: Double) {
        recording.events.append(RecordedEvent(kind: kind, t: time, output: nil, finger: nil, accepted: true,
                                              note: nil, audioOffset: nil, location: nil, promptIndex: promptIndex))
    }

    /// 目標を飛ばす(うまく打てないとき)
    func skip(at time: Double) {
        advance(at: time)
    }

    private func advance(at time: Double) {
        promptIndex += 1
        if let target = currentTarget {
            recording.prompts.append(RecordedPrompt(index: promptIndex, target: target, shownAt: time))
        }
    }

    /// 記録の課題を作る
    static func makeTask(kind: RecordingTask.Kind, count: Int, seed: UInt64) -> RecordingTask {
        switch kind {
        case .keys:
            // 打てる文字(a〜z と ; , . スペース)からランダムに選ぶ。毎回同じ並びにならないよう seed を変える
            let letters = Array("abcdefghijklmnopqrstuvwxyz;,. ").map(String.init)
            var state = seed &+ 0x9E3779B97F4A7C15
            var targets: [String] = []
            for _ in 0..<count {
                state = state &* 6364136223846793005 &+ 1442695040888963407
                targets.append(letters[Int((state >> 33) % UInt64(letters.count))])
            }
            return RecordingTask(kind: .keys, targets: targets)
        case .phrases:
            var targets: [String] = []
            let sentences = PracticeSession.sentences
            let start = Int(seed % UInt64(sentences.count))
            for i in 0..<max(1, count) {
                let sentence = sentences[(start + i) % sentences.count]
                targets += sentence.map(String.init)
                if i < count - 1 { targets.append(" ") }
            }
            return RecordingTask(kind: .phrases, targets: targets)
        case .kana:
            // フリック用: 短い仮名の語(言語モデルの学習データには入っていない語を中心に)
            let words = ["あさ", "いぬ", "うみ", "えき", "おかし", "かさ", "きつね", "くも", "けいと", "こえ",
                         "さる", "しま", "すいか", "せかい", "そら", "たこ", "ちず", "つき", "てがみ", "とり",
                         "なつ", "にわ", "ぬの", "ねこ", "のり", "はな", "ひかり", "ふね", "へや", "ほし",
                         "まど", "みかん", "むし", "めがね", "もり", "やま", "ゆき", "よる", "らいおん", "りんご",
                         "るす", "れもん", "ろうそく", "わたし", "がっこう", "でんしゃ", "ぱん", "きょう"]
            var state = seed &+ 0x9E3779B97F4A7C15
            var targets: [String] = []
            for _ in 0..<max(1, count) {
                state = state &* 6364136223846793005 &+ 1442695040888963407
                let word = words[Int((state >> 33) % UInt64(words.count))]
                targets += word.map(String.init)
            }
            return RecordingTask(kind: .kana, targets: targets)
        }
    }
}

/// 記録ファイルを読み込む(評価ツールの再生コマンドとテストで使う)
enum RecordingIO {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
