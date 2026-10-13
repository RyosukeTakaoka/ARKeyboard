import XCTest
@testable import ARKeyboardCore

/// タップ判定のテスト。60fps で、人工的な手の動きを作って流し込みます。
final class TapDetectorTests: XCTestCase {
    var fps = 60.0

    /// 指の動きの台本: 時刻 → 指先のずれ(手の座標。y が負 = 手首の方向 = 下ろす向き)
    typealias Script = (Double) -> Vec2

    /// 「素早く下ろして止める」動き。start 秒から duration 秒かけて depth だけ手首の方向へ動かし、そこで止める。
    static func tapScript(start: Double, duration: Double = 0.05, depth: Double = 0.15) -> Script {
        return { t in
            let progress = min(max((t - start) / duration, 0), 1)
            return Vec2(0, -depth * progress)
        }
    }

    /// 台本どおりに指を動かしてエンジンに流し込み、起きたタップを返す
    func run(engine: KeyboardEngine = KeyboardEngine(),
             finger: Finger = .index,
             hand: Chirality = .left,
             duration: Double = 1.0,
             base: (left: SyntheticHand, right: SyntheticHand) = standardHands(),
             handOffset: (Double) -> Vec2 = { _ in .zero },
             script: Script) -> [TapResult] {
        var taps: [TapResult] = []
        var t = 0.0
        while t <= duration {
            var left = base.left, right = base.right
            if hand == .left {
                left = left.moving(finger, by: script(t))
                left.origin += handOffset(t)
            } else {
                right = right.moving(finger, by: script(t))
                right.origin += handOffset(t)
            }
            taps += engine.process(makeFrame(time: t, hands: [left, right])).taps
            t += 1 / fps
        }
        return taps
    }

    func testQuickDownAndStopIsATap() {
        let taps = run(script: Self.tapScript(start: 0.3))
        XCTAssertEqual(taps.count, 1)
        XCTAssertEqual(taps.first?.event.finger, FingerID(chirality: .left, finger: .index))
        // 止まった時刻は動き終わり(0.35秒)の直後
        XCTAssertEqual(taps.first?.event.timestamp ?? 0, 0.35, accuracy: 0.05)
        // キャリブレーション前なのでキーは無い
        XCTAssertNil(taps.first?.key)
    }

    /// 30fps(暗い場所や古い機種)でも、普通の速さのタップは検出できる
    func testQuickTapAt30fps() {
        fps = 30
        XCTAssertEqual(run(script: Self.tapScript(start: 0.3, duration: 0.066, depth: 0.12)).count, 1)
    }

    func testSlowMovementIsNotATap() {
        // 同じ距離を 0.8 秒かけてゆっくり動かす
        XCTAssertTrue(run(script: Self.tapScript(start: 0.1, duration: 0.8)).isEmpty)
    }

    func testTinyJitterIsNotATap() {
        // 速いが、ほんの少し(0.02)しか動かない
        XCTAssertTrue(run(script: Self.tapScript(start: 0.3, duration: 0.03, depth: 0.02)).isEmpty)
    }

    func testUpwardMovementIsNotATap() {
        // 指を素早く「上げて」止める(手首から離れる向き)
        let up: Script = { t in -Self.tapScript(start: 0.3)(t) }
        XCTAssertTrue(run(script: up).isEmpty)
    }

    func testMovingWholeHandIsNotATap() {
        // 指は動かさず、手全体を素早く手前(画像の下)へ動かして止める
        let taps = run(handOffset: { t in Vec2(0, 60 * min(max((t - 0.3) / 0.05, 0), 1)) }, script: { _ in .zero })
        XCTAssertTrue(taps.isEmpty)
    }

    func testCooldownPreventsDoubleTap() {
        // 1回目のタップ → 素早く戻す → 0.1秒後に2回目(クールダウン 0.15 秒の内側)
        let script: Script = { t in
            if t < 0.36 { return Self.tapScript(start: 0.3)(t) }
            if t < 0.40 { return Vec2(0, -0.15 + 0.15 * (t - 0.36) / 0.04) }  // 戻す
            return Self.tapScript(start: 0.40)(t)
        }
        XCTAssertEqual(run(script: script).count, 1)
    }

    func testTwoSeparateTaps() {
        // 0.5 秒あけて2回
        let script: Script = { t in
            if t < 0.5 { return Self.tapScript(start: 0.2)(t) }
            if t < 0.6 { return Vec2(0, -0.15 + 0.15 * (t - 0.5) / 0.1) }  // ゆっくり戻す
            return Self.tapScript(start: 0.8)(t)
        }
        XCTAssertEqual(run(duration: 1.2, script: script).count, 2)
    }

    func testLowConfidenceIsIgnored() {
        var base = standardHands()
        base.left.confidence = 0.1
        XCTAssertTrue(run(base: base, script: Self.tapScript(start: 0.3)).isEmpty)
    }

    func testSensitivity() {
        // やや弱いタップ(0.07 を 0.1 秒で = 0.7 手/秒)
        let weak = Self.tapScript(start: 0.3, duration: 0.1, depth: 0.07)
        let sensitive = KeyboardEngine()
        sensitive.settings.sensitivity = 1.0
        XCTAssertEqual(run(engine: sensitive, script: weak).count, 1)
        let dull = KeyboardEngine()
        dull.settings.sensitivity = 0.0
        XCTAssertTrue(run(engine: dull, script: weak).isEmpty)
    }

    /// カメラが 90 度回っていても(手が横向きに映っても)判定できる
    func testRotatedCamera() {
        var base = standardHands()
        base.left.rotation = .pi / 2
        base.right.rotation = .pi / 2
        XCTAssertEqual(run(hand: .right, base: base, script: Self.tapScript(start: 0.3)).count, 1)
    }

    /// 隣の指がつられて少し遅れて動いても、タップは1回だけ
    func testSympatheticNeighborIsSuppressed() {
        let engine = KeyboardEngine()
        var taps: [TapResult] = []
        var t = 0.0
        let (left, right) = standardHands()
        while t <= 1 {
            let moved = left
                .moving(.index, by: Self.tapScript(start: 0.3)(t))
                .moving(.middle, by: Self.tapScript(start: 0.3, duration: 0.05, depth: 0.09)(t))
            taps += engine.process(makeFrame(time: t, hands: [moved, right])).taps
            t += 1 / fps
        }
        XCTAssertEqual(taps.count, 1)
        XCTAssertEqual(taps.first?.event.finger.finger, .index)
    }

    /// キャリブレーション後は、タップした指の位置のキーが入力される
    func testTapAfterCalibrationProducesKey() throws {
        let (left, right) = standardHands()
        let engine = KeyboardEngine()
        engine.setCalibration(CalibrationResult(
            left: try XCTUnwrap(Calibrator.makeCalibration(from: left.observation(), chirality: .left, config: .init())),
            right: try XCTUnwrap(Calibrator.makeCalibration(from: right.observation(), chirality: .right, config: .init())),
            createdAt: Date()))
        let leftCal = try XCTUnwrap(engine.calibration?.left)

        // ホーム位置のまま人差し指でタップ → F
        let home = run(engine: engine, script: Self.tapScript(start: 0.3, depth: 0.1))
        XCTAssertEqual(home.map { $0.key?.output }, ["f"])

        // 人差し指を奥(上段)に伸ばしてから下ろす → R
        let reach = leftCal.rowPitch
        let toR: Script = { t in Vec2(0, reach) + Self.tapScript(start: 0.3, depth: 0.08)(t) }
        let engine2 = KeyboardEngine()
        engine2.setCalibration(engine.calibration)
        // 伸ばした状態から始める(伸ばす動き自体はゆっくりなので、タップにならない)
        XCTAssertEqual(run(engine: engine2, script: toR).map { $0.key?.label }, ["R"])
    }

    /// 速度グラフ用のサンプルが出ていること
    func testSignalSampleForObservedFinger() {
        let engine = KeyboardEngine()
        engine.settings.debugFinger = FingerID(chirality: .left, finger: .index)
        var samples: [FingerSignalSample] = []
        var t = 0.0
        let (left, right) = standardHands()
        while t <= 0.6 {
            let output = engine.process(makeFrame(time: t, hands: [left.moving(.index, by: Self.tapScript(start: 0.3)(t)), right]))
            if let s = output.signalSample { samples.append(s) }
            t += 1 / fps
        }
        XCTAssertGreaterThan(samples.count, 30)
        XCTAssertGreaterThan(samples.map(\.speed).max() ?? 0, samples.first!.threshold)
        XCTAssertEqual(samples.filter(\.didTap).count, 1)
    }
}
