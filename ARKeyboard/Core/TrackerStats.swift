import Foundation

/// 手の追跡器(Vision / MediaPipe)を比べるための統計
struct TrackerStats: Equatable {
    /// 1秒あたりの処理コマ数
    var fps: Double = 0
    /// 1コマの手の検出にかかった時間の平均(ミリ秒)
    var processingMs: Double = 0
    /// 両手が見えていたコマの割合
    var twoHandRate: Double = 0
    /// 手のぶれ: 手のひらの中心が1コマで動いた量の中央値(手の大きさ単位)。
    /// 手を止めているときに小さいほど、安定して追跡できている
    var jitter: Double = 0
    /// 集めたコマの数
    var frames: Int = 0
}

/// 直近のコマから TrackerStats を計算する
struct TrackerStatsAccumulator {
    private var fpsCounter = FPSCounter()
    private var recent: [(processing: Double, twoHands: Bool, motion: Double?)] = []
    private var lastPalm: [Chirality: Vec2] = [:]
    private let window = 120
    private(set) var stats = TrackerStats()

    mutating func add(_ frame: VisionFrame, hands: [Chirality: HandObservation]) {
        var motion: Double?
        var motions: [Double] = []
        for (chirality, hand) in hands {
            guard let palm = TapDetector.palmCenter(of: hand, minConfidence: 0.3),
                  let handFrame = HandFrame(hand: hand, minConfidence: 0.3) else { continue }
            if let previous = lastPalm[chirality] {
                motions.append(previous.distance(to: palm) / handFrame.scale)
            }
            lastPalm[chirality] = palm
        }
        if !motions.isEmpty { motion = motions.reduce(0, +) / Double(motions.count) }
        recent.append((frame.processingTime, frame.hands.count >= 2, motion))
        if recent.count > window { recent.removeFirst(recent.count - window) }

        stats.fps = fpsCounter.tick(at: frame.timestamp)
        stats.processingMs = recent.map(\.processing).reduce(0, +) / Double(recent.count) * 1000
        stats.twoHandRate = Double(recent.filter(\.twoHands).count) / Double(recent.count)
        let motionValues = recent.compactMap(\.motion)
        stats.jitter = motionValues.isEmpty ? 0 : OnsetDetector.median(motionValues)
        stats.frames += 1
    }

    mutating func reset() {
        self = TrackerStatsAccumulator()
    }
}
