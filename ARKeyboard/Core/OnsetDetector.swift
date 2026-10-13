import Foundation

/// 「音の立ち上がり」や「振動のピクッ」などの、急な変化(オンセット)の検出結果
struct OnsetEvent: Equatable, Codable {
    enum Source: String, Codable {
        /// マイク(音)
        case audio
        /// 加速度センサー(iPhone 本体の振動)
        case motion
    }

    var source: Source
    /// 起きた時刻(秒、端末起動からの時間。カメラの撮影時刻と同じ基準)
    var time: Double
    /// 強さ(値 ÷ しきい値。1 を超えるほど強い)
    var strength: Double
}

/// オンセット検出の設定
struct OnsetDetectorConfig: Codable, Equatable {
    /// しきい値 = 直近の中央値 + k × ばらつき。k が大きいほど鈍感(雑音に強い)
    var k: Double = 6
    /// 雑音がほとんど無い静かな場所でも、これより小さい値は無視する(ばらつきの下限)
    var minSpread: Double = 1e-4
    /// 「直近」とみなす時間(秒)
    var historyDuration: Double = 0.5
    /// 1回検出したら、この時間は次を検出しない(1回の打鍵の余韻を何度も数えないため)
    var refractory: Double = 0.06
}

/// 数値の流れ(音のスペクトルの増え方・加速度の大きさ など)から、急な立ち上がりを見つける。
///
/// ## しきい値の決め方(適応しきい値)
/// 周りがうるさい場所と静かな場所では、「普段の値」が違います。固定のしきい値だと
/// どちらかで失敗するので、**直近 0.5 秒の値の中央値とばらつき**からしきい値を毎回決めます。
/// - 中央値: 値を並べた真ん中。平均と違って、たまに混ざる大きな値(打鍵そのもの)に引っ張られにくい。
/// - ばらつき: 中央絶対偏差(MAD)× 1.4826。正規分布なら標準偏差と同じくらいになる、外れ値に強い指標。
///
/// しきい値を「下から上へ越えた瞬間」をオンセットとします(山の頂上より、越えた瞬間の方が時刻が正確)。
///
/// Python の評価ツール(tools/eval/onset.py)にも同じ計算があり、結果が一致することをテストで確かめています。
final class OnsetDetector {
    var config: OnsetDetectorConfig
    let source: OnsetEvent.Source

    private var history: [(time: Double, value: Double)] = []
    private var wasAbove = false
    private var lastOnsetTime = -Double.infinity
    /// 最後に計算したしきい値(デバッグ表示用)
    private(set) var lastThreshold: Double = 0

    init(source: OnsetEvent.Source, config: OnsetDetectorConfig = OnsetDetectorConfig()) {
        self.source = source
        self.config = config
    }

    func reset() {
        history.removeAll()
        wasAbove = false
        lastOnsetTime = -Double.infinity
    }

    /// 値を1つ入れる。オンセットならそれを返す。
    func process(value: Double, time: Double) -> OnsetEvent? {
        // 古い値を捨てる
        let oldest = time - config.historyDuration
        if let firstKeep = history.firstIndex(where: { $0.time >= oldest }) {
            if firstKeep > 0 { history.removeFirst(firstKeep) }
        } else {
            history.removeAll()
        }

        var event: OnsetEvent?
        // 直近の値が少なすぎるうちは、しきい値を決められないので判定しない
        if history.count >= 8 {
            let values = history.map(\.value)
            let median = Self.median(values)
            let mad = Self.median(values.map { abs($0 - median) }) * 1.4826
            let threshold = median + config.k * max(mad, config.minSpread)
            lastThreshold = threshold
            let isAbove = value > threshold
            if isAbove && !wasAbove && time - lastOnsetTime >= config.refractory {
                event = OnsetEvent(source: source, time: time, strength: value / threshold)
                lastOnsetTime = time
            }
            wasAbove = isAbove
        }
        history.append((time, value))
        return event
    }

    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
}

/// 音の 1 区間(ホップ)分の特徴。iPhone 側(AudioOnsetSensor)が Accelerate で計算して作る。
struct AudioFeature: Equatable, Codable {
    /// 区間の時刻(秒)
    var time: Double
    /// 音の大きさ(RMS)
    var rms: Double
    /// スペクトルの増え方(spectral flux)。前の区間より大きくなった周波数成分の合計。
    /// 叩いたときの「パチッ」という急な音で大きくなる。
    var flux: Double
    /// その時点のオンセットのしきい値(デバッグ表示用)
    var threshold: Double = 0
}

/// 加速度の 1 サンプル(iPhone 本体の動き。重力を除いた値、単位は G)
struct MotionSample: Equatable, Codable {
    var time: Double
    var x: Double
    var y: Double
    var z: Double
}
