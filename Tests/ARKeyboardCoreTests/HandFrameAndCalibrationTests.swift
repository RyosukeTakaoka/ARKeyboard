import XCTest
@testable import ARKeyboardCore

final class HandFrameTests: XCTestCase {
    func testLocalCoordinatesMatchSyntheticHand() throws {
        let hand = SyntheticHand(chirality: .left)
        let frame = try XCTUnwrap(HandFrame(hand: hand.observation(), minConfidence: 0.3))
        let local = frame.toLocal(hand.imagePoint(Vec2(0.35, 1.55)))
        XCTAssertEqual(local.x, 0.35, accuracy: 1e-6)
        XCTAssertEqual(local.y, 1.55, accuracy: 1e-6)
        XCTAssertEqual(frame.scale, 150, accuracy: 1e-6)
        // 左手を上から見ると、親指側は画像の右(+x)
        XCTAssertEqual(frame.thumbward.x, 1, accuracy: 1e-6)
        XCTAssertEqual(frame.handedness, .left)
    }

    /// カメラが回転していても(手が斜めに映っても)、手の座標は変わらないこと
    func testRotationInvariance() throws {
        for degrees in [0.0, 37, 90, 180, 250] {
            for chirality in Chirality.allCases {
                let hand = SyntheticHand(chirality: chirality, rotation: degrees * .pi / 180, scale: 90)
                let frame = try XCTUnwrap(HandFrame(hand: hand.observation(), minConfidence: 0.3))
                let local = frame.toLocal(hand.imagePoint(Vec2(-0.42, 1.45)))
                XCTAssertEqual(local.x, -0.42, accuracy: 1e-6, "\(chirality) \(degrees)°")
                XCTAssertEqual(local.y, 1.45, accuracy: 1e-6, "\(chirality) \(degrees)°")
                XCTAssertEqual(frame.handedness, chirality, "\(chirality) \(degrees)°")
                // 逆変換で元に戻る
                let image = frame.toImage(local)
                XCTAssertEqual(image.distance(to: hand.imagePoint(Vec2(-0.42, 1.45))), 0, accuracy: 1e-6)
            }
        }
    }

    func testMissingJointsGiveNil() {
        var hand = SyntheticHand(chirality: .right)
        hand.local[.middleMCP] = nil
        XCTAssertNil(HandFrame(hand: hand.observation(), minConfidence: 0.3))
        // 信頼度が低い場合も使わない
        let low = SyntheticHand(chirality: .right, confidence: 0.1)
        XCTAssertNil(HandFrame(hand: low.observation(), minConfidence: 0.3))
    }
}

final class CalibrationTests: XCTestCase {
    /// 両手を 2 秒以上静止させると、キャリブレーションが完了すること
    func testCalibrationCompletesAfterHoldingStill() throws {
        let (left, right) = standardHands()
        let engine = KeyboardEngine()
        engine.startCalibration()

        var result: CalibrationResult?
        var t = 0.0
        while t < 2.5, result == nil {
            // ごく小さな手ぶれ(静止とみなせる範囲)を加える
            let jitter = Vec2(sin(t * 40) * 0.01, cos(t * 33) * 0.01)
            let frame = makeFrame(time: t, hands: [left.moving(.index, by: jitter), right])
            result = engine.process(frame).calibrationFinished
            t += 1.0 / 30
        }
        let calibration = try XCTUnwrap(result)
        XCTAssertGreaterThanOrEqual(t, 2.0)
        XCTAssertEqual(engine.calibrator.phase, .finished)

        // ホーム位置(左手の人差し指=F)が手の座標で記録されている
        let leftIndex = try XCTUnwrap(calibration.left.homeTips[.index])
        XCTAssertEqual(leftIndex.x, 0.35, accuracy: 0.02)
        XCTAssertEqual(leftIndex.y, 1.55, accuracy: 0.02)
        // 隣り合う指先の間隔の平均 ≒ 0.27
        XCTAssertEqual(calibration.left.keyPitch, 0.27, accuracy: 0.02)
        XCTAssertEqual(calibration.right.keyPitch, 0.27, accuracy: 0.02)
        // 真上から撮っているので、奥行きの縮みはほぼ無い
        XCTAssertEqual(calibration.left.foreshortening, 1, accuracy: 0.05)
        XCTAssertNotNil(calibration.right.homeTips[.thumb])
    }

    /// 途中で手が動いたら計測をやり直すこと
    func testMovementRestartsHolding() {
        let (left, right) = standardHands()
        let engine = KeyboardEngine()
        engine.startCalibration()
        var t = 0.0
        while t < 1.5 {
            _ = engine.process(makeFrame(time: t, hands: [left, right]))
            t += 1.0 / 30
        }
        // 大きく動かす(手の大きさの 30%)。直近の数フレームの平均で判定するので、数フレーム以内にやり直しになる
        let moved = left.moving(.middle, by: Vec2(0, 0.3))
        var restarted = false
        for _ in 0..<3 {
            _ = engine.process(makeFrame(time: t, hands: [moved, right]))
            t += 1.0 / 30
            if engine.calibrator.phase == .holding(progress: 0) { restarted = true; break }
        }
        XCTAssertTrue(restarted)
        // 片手しか映っていなければ待機に戻る
        _ = engine.process(makeFrame(time: t + 0.1, hands: [right]))
        XCTAssertEqual(engine.calibrator.phase, .waitingForHands)
    }

    /// 斜めから撮って前後が縮んで見えるとき、行の間隔が補正されること
    func testForeshorteningIsEstimated() throws {
        var hand = SyntheticHand(chirality: .left)
        hand.forwardSquash = 0.6
        let calibration = try XCTUnwrap(
            Calibrator.makeCalibration(from: hand.observation(), chirality: .left, config: Calibrator.Config()))
        // 手のひらの幅 0.755 / 手の長さ 1 ≒ 0.75 の手が、0.6 に縮んで見えている
        XCTAssertEqual(calibration.foreshortening, 0.6, accuracy: 0.05)
        XCTAssertEqual(calibration.rowPitch, calibration.keyPitch * calibration.foreshortening, accuracy: 1e-9)
    }
}

final class HandAssignmentTests: XCTestCase {
    func testUnknownChiralityIsGuessedFromShape() {
        let (left, right) = standardHands()
        let engine = KeyboardEngine()
        let hands = engine.assignHands([
            left.observation(reportedChirality: .some(nil)),
            right.observation(reportedChirality: .some(nil)),
        ])
        XCTAssertEqual(hands[.left]?.joints[.wrist]?.position, left.observation().joints[.wrist]?.position)
        XCTAssertEqual(hands[.right]?.joints[.wrist]?.position, right.observation().joints[.wrist]?.position)
    }

    func testSwapHandsSetting() {
        let (left, right) = standardHands()
        var settings = KeyboardSettings()
        settings.swapHands = true
        let engine = KeyboardEngine(settings: settings)
        let hands = engine.assignHands([left.observation(), right.observation()])
        XCTAssertEqual(hands[.right]?.joints[.wrist]?.position, left.observation().joints[.wrist]?.position)
    }
}

final class CalibrationRobustnessTests: XCTestCase {
    /// 関節点が震えていても(手の大きさの 2%)、キャリブレーションは完了する
    func testCompletesWithJointJitter() {
        let (left, right) = standardHands()
        let engine = KeyboardEngine()
        engine.startCalibration()
        var rng = SplitMix64(seed: 7)
        var t = 0.0
        while engine.calibration == nil, t < 6 {
            let frame = Replayer.addNoise(to: makeFrame(time: t, hands: [left, right]), sigma: 0.02, rng: &rng)
            _ = engine.process(frame)
            t += 1.0 / 30
        }
        XCTAssertNotNil(engine.calibration)
        XCTAssertLessThan(t, 3)
    }
}
