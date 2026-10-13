import XCTest
@testable import ARKeyboardCore

final class OnsetDetectorTests: XCTestCase {
    /// 小さな雑音の中に、急に大きな値が来たらオンセット
    func testDetectsSpikeInNoise() {
        let detector = OnsetDetector(source: .audio)
        var onsets: [OnsetEvent] = []
        var rng = SeededRandom(seed: 1)
        for i in 0..<300 {
            let t = Double(i) * 0.01
            var value = 0.01 + rng.next() * 0.005
            if i == 150 || i == 151 { value = 0.2 }  // 1.5秒のところで叩いた
            if let e = detector.process(value: value, time: t) { onsets.append(e) }
        }
        XCTAssertEqual(onsets.count, 1)
        XCTAssertEqual(onsets.first?.time ?? 0, 1.5, accuracy: 1e-9)
        XCTAssertGreaterThan(onsets.first?.strength ?? 0, 1)
    }

    /// うるさい場所(雑音が大きい)では、同じ大きさの値でもオンセットにならない(適応しきい値)
    func testAdaptsToLoudEnvironment() {
        let detector = OnsetDetector(source: .audio)
        var count = 0
        var rng = SeededRandom(seed: 2)
        for i in 0..<300 {
            let t = Double(i) * 0.01
            var value = 0.1 + rng.next() * 0.1
            if i == 150 { value = 0.25 }
            if detector.process(value: value, time: t) != nil { count += 1 }
        }
        XCTAssertEqual(count, 0)
    }

    /// 余韻(続けて大きい値)を何度も数えない
    func testRefractory() {
        let detector = OnsetDetector(source: .motion)
        var count = 0
        for i in 0..<100 {
            let t = Double(i) * 0.01
            let value = (i >= 50 && i % 2 == 0) ? 1.0 : 0.001 * Double(i % 3)
            if detector.process(value: value, time: t) != nil { count += 1 }
        }
        // 0.5秒〜1秒の間に 0.02 秒おきの山。不応期 0.06 秒なので、およそ 25/3 回程度に間引かれる
        XCTAssertLessThan(count, 12)
        XCTAssertGreaterThan(count, 3)
    }
}

final class SensorFusionTests: XCTestCase {
    func onset(_ t: Double, _ source: OnsetEvent.Source = .audio) -> OnsetEvent {
        OnsetEvent(source: source, time: t, strength: 2)
    }

    func testAcceptsWhenAudioInWindow() {
        let fusion = SensorFusion<Int>()
        fusion.addOnsets([], source: .audio, coveredUntil: 0.9, now: 0.9)
        fusion.addCandidate(time: 1.0, payload: 1)
        // まだ音のデータが 1.06 まで届いていないので保留
        XCTAssertTrue(fusion.resolve(now: 1.0).isEmpty)
        fusion.addOnsets([onset(0.97)], source: .audio, coveredUntil: 1.1, now: 1.1)
        let decisions = fusion.resolve(now: 1.1)
        XCTAssertEqual(decisions.count, 1)
        XCTAssertEqual(decisions.first?.accepted, true)
        XCTAssertEqual(decisions.first?.audio?.time ?? 0, 0.97, accuracy: 1e-9)
    }

    func testRejectsWhenNoAudio() {
        let fusion = SensorFusion<Int>()
        fusion.addOnsets([onset(0.5)], source: .audio, coveredUntil: 0.9, now: 0.9)
        fusion.addCandidate(time: 1.0, payload: 1)
        fusion.addOnsets([], source: .audio, coveredUntil: 1.2, now: 1.2)
        let decisions = fusion.resolve(now: 1.2)
        XCTAssertEqual(decisions.first?.accepted, false)
        XCTAssertEqual(decisions.first?.note, "音なし")
    }

    func testFallsBackToVisionWhenMicIsNotRunning() {
        let fusion = SensorFusion<Int>()
        fusion.addCandidate(time: 1.0, payload: 1)
        let decisions = fusion.resolve(now: 1.0)
        XCTAssertEqual(decisions.first?.accepted, true)
        XCTAssertNotNil(decisions.first?.note)
    }

    func testDisabledAudioAcceptsImmediately() {
        let fusion = SensorFusion<Int>()
        fusion.useAudio = false
        fusion.addOnsets([], source: .audio, coveredUntil: 0.9, now: 0.9)
        fusion.addCandidate(time: 1.0, payload: 1)
        XCTAssertEqual(fusion.resolve(now: 1.0).first?.accepted, true)
    }

    func testFeedbackMuteIgnoresOwnClick() {
        let fusion = SensorFusion<Int>()
        fusion.addOnsets([], source: .audio, coveredUntil: 0.9, now: 0.9)
        fusion.muteFeedback(at: 0.95)  // 自分のクリック音
        fusion.addCandidate(time: 1.0, payload: 1)
        fusion.addOnsets([onset(0.98)], source: .audio, coveredUntil: 1.2, now: 1.2)
        XCTAssertEqual(fusion.resolve(now: 1.2).first?.accepted, false)
    }

    func testMotionCountsWhenEnabled() {
        let fusion = SensorFusion<Int>()
        fusion.useAudio = false
        fusion.useMotion = true
        fusion.addOnsets([onset(1.01, .motion)], source: .motion, coveredUntil: 1.2, now: 1.2)
        fusion.addCandidate(time: 1.0, payload: 1)
        let decision = fusion.resolve(now: 1.2).first
        XCTAssertEqual(decision?.accepted, true)
        XCTAssertNotNil(decision?.motion)
    }

    /// エンジン経由: 音があるタップは入力され、音が無いタップは却下される
    func testEngineRequiresAudioWhenMicIsRunning() throws {
        let (left, right) = standardHands()
        let calibration = CalibrationResult(
            left: try XCTUnwrap(Calibrator.makeCalibration(from: left.observation(), chirality: .left, config: .init())),
            right: try XCTUnwrap(Calibrator.makeCalibration(from: right.observation(), chirality: .right, config: .init())),
            createdAt: Date())

        func run(withSound: Bool) -> [TapResult] {
            let engine = KeyboardEngine()
            engine.setCalibration(calibration)
            var results: [TapResult] = []
            var t = 0.0
            while t <= 1.0 {
                let moved = left.moving(.index, by: TapDetectorTests.tapScript(start: 0.3)(t))
                results += engine.process(makeFrame(time: t, hands: [moved, right]), now: t)
                    .taps
                // マイクは 10ms ごとに解析が進む。0.34 秒(指が当たった頃)に音
                let sound = withSound && abs(t - 0.34) < 0.009 ? [OnsetEvent(source: .audio, time: 0.34, strength: 3)] : []
                results += engine.ingestOnsets(sound, source: .audio, coveredUntil: t, now: t)
                t += 1.0 / 60
            }
            return results
        }

        let withSound = run(withSound: true)
        XCTAssertEqual(withSound.map { $0.key?.label }, ["F"])
        XCTAssertEqual(withSound.first?.audioOffset ?? 1, 0.34 - (withSound.first?.event.timestamp ?? 0), accuracy: 1e-9)
        XCTAssertTrue(withSound.first?.touch?.evidence.contains(.audio) ?? false)

        let silent = run(withSound: false)
        XCTAssertEqual(silent.count, 1)
        XCTAssertNil(silent.first?.key)
        XCTAssertEqual(silent.first?.note, "音なし")
    }
}

/// テスト用の再現できる乱数(毎回同じ値の列になる)
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }
    /// 0〜1 の乱数
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(1 << 53)
    }
}
