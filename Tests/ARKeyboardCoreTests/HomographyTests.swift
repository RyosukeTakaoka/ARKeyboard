import XCTest
@testable import ARKeyboardCore

final class HomographyTests: XCTestCase {
    /// 斜めから見た机(台形に映る)の四隅
    let trapezoid = [Vec2(220, 500), Vec2(500, 500), Vec2(680, 1100), Vec2(40, 1100)]

    func testMapsCornersExactly() throws {
        let plane = DeskPlane(imageCorners: trapezoid, widthCm: 60, depthCm: 40)
        let h = try XCTUnwrap(plane.imageToPlane)
        let expected = [Vec2(0, 0), Vec2(60, 0), Vec2(60, 40), Vec2(0, 40)]
        for (src, dst) in zip(trapezoid, expected) {
            let p = try XCTUnwrap(h.apply(src))
            XCTAssertEqual(p.x, dst.x, accuracy: 1e-6)
            XCTAssertEqual(p.y, dst.y, accuracy: 1e-6)
        }
    }

    func testInverseRoundTrip() throws {
        let plane = DeskPlane(imageCorners: trapezoid, widthCm: 60, depthCm: 40)
        let h = try XCTUnwrap(plane.imageToPlane)
        let inv = try XCTUnwrap(h.inverse)
        let p = Vec2(333, 777)
        let back = try XCTUnwrap(inv.apply(try XCTUnwrap(h.apply(p))))
        XCTAssertEqual(back.distance(to: p), 0, accuracy: 1e-6)
        // planeToImage と inverse は同じ変換
        let p2 = try XCTUnwrap(plane.planeToImage?.apply(Vec2(10, 20)))
        let p3 = try XCTUnwrap(inv.apply(Vec2(10, 20)))
        XCTAssertEqual(p2.distance(to: p3), 0, accuracy: 1e-6)
    }

    func testDegenerateCornersGiveNil() {
        // 4点が一直線
        let line = [Vec2(0, 0), Vec2(1, 1), Vec2(2, 2), Vec2(3, 3)]
        XCTAssertNil(DeskPlane(imageCorners: line, widthCm: 60, depthCm: 40).imageToPlane)
    }

    /// 机モード: 遠近法でゆがんだ画像でも、ホモグラフィーで直せば、
    /// 真上から見たときと同じように手の座標(キーの位置)を測れる
    func testRectifiedHandMatchesTopView() throws {
        // 真上から見た机の座標(cm)で置いた手(手首〜中指付け根 9cm)
        let top = SyntheticHand(chirality: .left, origin: Vec2(20, 30), rotation: 0, scale: 9)
        let plane = DeskPlane(imageCorners: trapezoid, widthCm: 60, depthCm: 40)
        let planeToImage = try XCTUnwrap(plane.planeToImage)
        // 画像に映った手 = 机の座標を逆の変換で画像に写したもの
        var imageHand = top.observation()
        for (joint, point) in imageHand.joints {
            imageHand.joints[joint]?.position = try XCTUnwrap(planeToImage.apply(point.position))
        }
        // 画像のままだと、遠近法で指の間隔がゆがむ
        let rawFrame = try XCTUnwrap(HandFrame(hand: imageHand, minConfidence: 0.3))
        let rawLocal = rawFrame.toLocal(try XCTUnwrap(imageHand.position(.littleTip, minConfidence: 0.3)))
        // 直すと、真上から見た手の座標(-0.42, 1.45)に戻る
        let rectified = plane.rectify(imageHand, using: try XCTUnwrap(plane.imageToPlane))
        let frame = try XCTUnwrap(HandFrame(hand: rectified, minConfidence: 0.3))
        let local = frame.toLocal(try XCTUnwrap(rectified.position(.littleTip, minConfidence: 0.3)))
        XCTAssertEqual(local.x, -0.42, accuracy: 1e-6)
        XCTAssertEqual(local.y, 1.45, accuracy: 1e-6)
        XCTAssertGreaterThan(rawLocal.distance(to: Vec2(-0.42, 1.45)), 0.01)
    }

    /// エンジン経由: 机モード + 四隅登録で、キーの判定ができる
    func testEngineUsesDeskPlaneInDeskMode() throws {
        let plane = DeskPlane(imageCorners: trapezoid, widthCm: 60, depthCm: 40)
        let planeToImage = try XCTUnwrap(plane.planeToImage)
        func toImage(_ hand: SyntheticHand) -> HandObservation {
            var obs = hand.observation()
            for (joint, point) in obs.joints {
                obs.joints[joint]?.position = planeToImage.apply(point.position)!
            }
            return obs
        }
        let left = SyntheticHand(chirality: .left, origin: Vec2(18, 32), scale: 9)
        let right = SyntheticHand(chirality: .right, origin: Vec2(42, 32), scale: 9)

        var settings = KeyboardSettings.defaults(for: .desk)
        settings.features.audioOnset = false
        let engine = KeyboardEngine(settings: settings)
        engine.deskPlane = plane
        XCTAssertTrue(engine.isUsingDeskPlane)
        engine.startCalibration()
        var t = 0.0
        while engine.calibration == nil, t < 3 {
            _ = engine.process(VisionFrame(timestamp: t, imageSize: Vec2(720, 1280), hands: [toImage(left), toImage(right)]))
            t += 1.0 / 30
        }
        XCTAssertNotNil(engine.calibration)
        let output = engine.process(VisionFrame(timestamp: t, imageSize: Vec2(720, 1280), hands: [toImage(left), toImage(right)]))
        XCTAssertTrue(output.hoveredKeyIDs.contains("left-F"))
        XCTAssertTrue(output.hoveredKeyIDs.contains("right-J"))
        XCTAssertNotNil(output.planeToImage)
        // 画面表示用の手は、画像の座標のまま
        XCTAssertEqual(output.hands[.left]?.joints[.wrist]?.position, toImage(left).joints[.wrist]?.position)
    }
}

final class HomographyAccuracyTests: XCTestCase {
    /// 9 点の最小二乗: 誤差の無い点なら元の変換をそのまま復元する(4 点のときと一致)
    func testLeastSquaresRecoversExactHomography() throws {
        let camera = DeskAccuracySimulation.Camera()
        let grid = (0..<9).map { Vec2(Double($0 % 3) * 15, Double($0 / 3) * 7.5) }
        let plane9 = DeskPlane(gridPoints: grid.map { camera.project($0, width: 30, depth: 15) }, widthCm: 30, depthCm: 15)
        let h = try XCTUnwrap(plane9.imageToPlane)
        for p in [Vec2(3, 4), Vec2(27, 12), Vec2(15, 7.5)] {
            let back = try XCTUnwrap(h.apply(camera.project(p, width: 30, depth: 15)))
            XCTAssertEqual(back.distance(to: p), 0, accuracy: 1e-6)
        }
        XCTAssertEqual(plane9.imageCorners.count, 4)
    }

    /// 正規化: 大きな座標(数千ピクセル)でも、正しく解ける
    func testNormalizationHandlesLargeCoordinates() throws {
        let src = [Vec2(10000, 20000), Vec2(14000, 20500), Vec2(13800, 24000), Vec2(10300, 23800)]
        let dst = [Vec2(0, 0), Vec2(30, 0), Vec2(30, 15), Vec2(0, 15)]
        let h = try XCTUnwrap(Homography(from: src, to: dst))
        for (a, b) in zip(src, dst) {
            XCTAssertEqual(try XCTUnwrap(h.apply(a)).distance(to: b), 0, accuracy: 1e-6)
        }
    }

    /// 見積もり: 指先で平均して登録するほうが、画面タップより誤差が小さい。9 点はさらに小さい
    func testFingertipRegistrationIsMoreAccurate() {
        let tap = DeskAccuracySimulation.run(method: .tap4, trials: 200).mean
        let finger4 = DeskAccuracySimulation.run(method: .finger4, trials: 200).mean
        let finger9 = DeskAccuracySimulation.run(method: .finger9, trials: 200).mean
        XCTAssertLessThan(finger4, tap)
        XCTAssertLessThan(finger9, finger4)
    }

    /// 指先が 0.8 秒止まったら、その間の平均を 1 点として記録。離れるまで次は記録しない
    func testFingertipCapture() throws {
        let capture = FingertipPointCapture()
        var rng = SplitMix64(seed: 2)
        var captured: [Vec2] = []
        var t = 0.0
        func feed(_ p: Vec2, seconds: Double) {
            let end = t + seconds
            while t < end {
                let noisy = p + Vec2(rng.nextGaussian(), rng.nextGaussian()) * 1.5
                if let c = capture.process(fingertip: noisy, time: t) { captured.append(c) }
                t += 1.0 / 30
            }
        }
        feed(Vec2(100, 100), seconds: 2.0)   // 長く止まっても 1 回だけ
        feed(Vec2(400, 120), seconds: 1.2)   // 次の角
        XCTAssertEqual(captured.count, 2)
        XCTAssertEqual(try XCTUnwrap(captured.first).distance(to: Vec2(100, 100)), 0, accuracy: 1.5)
    }
}
