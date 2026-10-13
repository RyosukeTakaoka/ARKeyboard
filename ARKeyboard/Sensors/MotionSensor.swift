import CoreMotion

/// 加速度センサーの解析結果(メインスレッドに届ける)
struct MotionUpdate {
    var samples: [MotionSample]
    var onsets: [OnsetEvent]
    var coveredUntil: Double
}

/// iPhone 本体の加速度(CoreMotion)から、机を叩いたときの「ピクッ」という振動を見つけるクラス。
///
/// 机モードで iPhone を同じ机に置いているときに、タップの裏付けとして使えます。
/// (手に持っている・膝の上では、手の揺れの方が大きいので役に立ちにくい)
///
/// - 重力を除いた加速度(userAcceleration)を 100Hz で受け取る。
/// - 「前のサンプルとの差の大きさ」(急な変化)を OnsetDetector に入れる。
///   叩いた振動は一瞬で変化するので、ゆっくりした傾きの変化より大きく出る。
/// - CMDeviceMotion.timestamp は「端末起動からの秒数」なので、カメラの時刻とそのまま比べられる。
final class MotionSensor {
    var onUpdate: ((MotionUpdate) -> Void)?

    private let manager = CMMotionManager()
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "ARKeyboard.motion"
        // 1つずつ順番に処理する(並列にすると、前後の差の計算が壊れるため)
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    // ↓ queue の中でだけ使う
    private var detector = OnsetDetector(source: .motion)
    private var previous: MotionSample?
    private var batch: [MotionSample] = []
    private var batchOnsets: [OnsetEvent] = []

    static var isAvailable: Bool {
        CMMotionManager().isDeviceMotionAvailable
    }

    var isRunning: Bool { manager.isDeviceMotionActive }

    func start(config: OnsetDetectorConfig) {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        queue.addOperation { [weak self] in
            self?.detector.config = config
        }
        manager.deviceMotionUpdateInterval = 1.0 / 100
        manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.handle(motion)
        }
    }

    func updateConfig(_ config: OnsetDetectorConfig) {
        queue.addOperation { [weak self] in
            self?.detector.config = config
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }

    private func handle(_ motion: CMDeviceMotion) {
        let a = motion.userAcceleration
        let sample = MotionSample(time: motion.timestamp, x: a.x, y: a.y, z: a.z)
        if let previous {
            let dx = sample.x - previous.x, dy = sample.y - previous.y, dz = sample.z - previous.z
            let change = (dx * dx + dy * dy + dz * dz).squareRoot()
            if let onset = detector.process(value: change, time: sample.time) {
                batchOnsets.append(onset)
            }
        }
        previous = sample
        batch.append(sample)

        // 1サンプルずつメインスレッドに送ると負担なので、5個(50ms)ずつまとめて送る
        if batch.count >= 5 {
            let update = MotionUpdate(samples: batch, onsets: batchOnsets, coveredUntil: sample.time)
            batch = []
            batchOnsets = []
            DispatchQueue.main.async { [weak self] in
                self?.onUpdate?(update)
            }
        }
    }
}
