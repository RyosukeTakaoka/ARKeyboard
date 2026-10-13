import XCTest
@testable import ARKeyboardCore

final class HandwritingTests: XCTestCase {
    /// つまんだ(ペンを下ろした)手を、画像の上で動かす。
    /// - Parameter move: 書く座標での動き(x: 手から見て右、y: 手の前)。画像の上の動きに変換して手全体を動かす
    func write(rotation: Double, mirror: Bool = false, path: (Double) -> Vec2) -> [HandwritingStroke] {
        let recorder = HandwritingRecorder()
        recorder.config.mirror = mirror
        recorder.config.finishDelay = 0.5
        var base = SyntheticHand(chirality: .right, origin: Vec2(360, 700))
        base.rotation = rotation
        // 手から見た「右」(手の甲側から見て、前を時計回りに 90 度)と「前」の、画像での向き
        let forward = base.forwardAxis
        let right = Vec2(-forward.y, forward.x)
        var finished: [HandwritingStroke]?
        var t = 0.0
        while t <= 2.0 {
            var hand = base
            let writing = t < 1.0
            if writing {
                hand.local[.thumbTip] = hand.local[.indexTip]! + Vec2(0.05, 0)  // つまむ
                let p = path(t)
                hand.origin = base.origin + right * (p.x * hand.scale) + forward * (p.y * hand.scale)
            }
            let observation = hand.observation()
            let frame = HandFrame(hand: observation, minConfidence: 0.3)
            if let result = recorder.process(hand: observation, frame: frame, time: t, minConfidence: 0.3) {
                finished = result
            }
            t += 1.0 / 30
        }
        return finished ?? []
    }

    /// 横線を右へ: 画像の中で手がどちらを向いていても、書く座標では「右へ」になる(画像の上下左右を使わない)
    func testDirectionIndependentOfImageRotation() throws {
        for rotation in [0, Double.pi / 2, Double.pi, -Double.pi / 3] {
            let strokes = write(rotation: rotation) { t in Vec2(t, 0) }
            let stroke = try XCTUnwrap(strokes.first, "rotation \(rotation)")
            let d = try XCTUnwrap(stroke.points.last) - stroke.points[0]
            XCTAssertGreaterThan(d.x, 0.8, "rotation \(rotation)")
            XCTAssertEqual(d.y, 0, accuracy: 0.05, "rotation \(rotation)")
        }
    }

    func testMirrorFlipsHorizontal() throws {
        let strokes = write(rotation: 0, mirror: true) { t in Vec2(t, 0) }
        let stroke = try XCTUnwrap(strokes.first)
        XCTAssertLessThan(try XCTUnwrap(stroke.points.last).x - stroke.points[0].x, -0.8)
    }

    /// 画像にすると、右へ書いた横線は画像の左から右へ、上へ書いた縦線は画像の下から上へ伸びる
    func testRasterizeOrientation() {
        let size = 40
        let horizontal = HandwritingRecorder.rasterize([HandwritingStroke(points: [Vec2(0, 0), Vec2(1, 0)])], size: size, lineWidth: 2)
        let row = size / 2
        XCTAssertEqual(horizontal[row * size + size / 2], 0)  // 中央は黒
        XCTAssertEqual(horizontal[2 * size + size / 2], 255)  // 上のほうは白
        // 「L」の字: 縦線(上から下)+ 横線(右へ)。左下の角が黒、右上は白
        let l = HandwritingRecorder.rasterize([HandwritingStroke(points: [Vec2(0, 1), Vec2(0, 0), Vec2(1, 0)])],
                                              size: size, lineWidth: 2)
        let lo = Int(Double(size) * 0.15) + 1, hi = Int(Double(size) * 0.85) - 1
        XCTAssertEqual(l[hi * size + lo], 0)
        XCTAssertEqual(l[lo * size + hi], 255)
    }

    /// ペンを上げずにいる間は認識に回らず、上げて待ち時間がたったら1回だけ渡す
    func testFinishesOnceAfterDelay() {
        let strokes = write(rotation: 0) { t in Vec2(t, t) }
        XCTAssertEqual(strokes.count, 1)
        XCTAssertGreaterThan(strokes[0].points.count, 20)
    }
}
