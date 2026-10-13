import Foundation

/// 1秒間に何コマ処理できているか(FPS)を数える。
/// 撮影時刻を渡すたびに、直近1秒間のコマ数から FPS を計算します。
struct FPSCounter {
    /// 何秒分の記録から計算するか
    var window: Double = 1.0
    private var times: [Double] = []

    /// 1コマ処理したことを記録し、現在の FPS を返す
    mutating func tick(at time: Double) -> Double {
        times.append(time)
        // 古い記録を捨てる
        while let first = times.first, time - first > window {
            times.removeFirst()
        }
        guard times.count >= 2, let first = times.first, let last = times.last, last > first else { return 0 }
        // 「間隔の数 ÷ かかった時間」
        return Double(times.count - 1) / (last - first)
    }
}

/// デバッグ表示用の、タップ1回分の記録
struct TapLogEntry: Identifiable, Equatable {
    /// 通し番号(画面のリスト表示で使う ID)
    let id: Int
    var timestamp: Double
    var finger: FingerID
    /// 入力されたキー(入力されなかったときは nil)
    var keyLabel: String?
    /// 下ろしたときの最大の速さ(手/秒)
    var peakSpeed: Double
    /// 下ろした距離(手)
    var travel: Double
    /// 入力されなかった理由など
    var note: String?
    /// LiDAR で測った、面からの高さ(メートル)
    var heightAboveSurface: Double?
    /// 音のオンセットとのずれ(秒、音の時刻 − カメラの時刻)
    var audioOffset: Double?
    /// タップの確からしさ
    var confidence: Double?

    init(id: Int, result: TapResult) {
        self.id = id
        timestamp = result.event.timestamp
        finger = result.event.finger
        keyLabel = result.key?.label
        peakSpeed = result.event.peakSpeed
        travel = result.event.travel
        note = result.note
        heightAboveSurface = result.heightAboveSurface
        audioOffset = result.audioOffset
        confidence = result.touch?.confidence
    }

    /// 1行の説明(例: "右手の人差し指 → J  速さ2.31 移動0.112")
    var summary: String {
        let key = keyLabel.map { "→ \($0)" } ?? "→ (\(note ?? "なし"))"
        let height = heightAboveSurface.map { String(format: " 高さ%.1fcm", $0 * 100) } ?? ""
        let audio = audioOffset.map { String(format: " 音%+.0fms", $0 * 1000) } ?? ""
        return "\(finger.japaneseName) \(key)  速さ\(String(format: "%.2f", peakSpeed)) 移動\(String(format: "%.3f", travel))\(audio)\(height)"
    }
}
