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
