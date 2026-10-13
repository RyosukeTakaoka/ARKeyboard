import XCTest
@testable import ARKeyboardCore

/// 縦向き画像のピクセル座標を受け取って深さを返す関数から、横長(センサー向き)の深度マップを作る
func makeDepthMap(imageSize: Vec2 = Vec2(720, 1280), width: Int = 96, height: Int = 72,
                  depthAt: (Vec2) -> Float) -> DepthMap {
    var values = [Float](repeating: 0, count: width * height)
    for y in 0..<height {
        for x in 0..<width {
            let bx = (Double(x) + 0.5) / Double(width)
            let by = (Double(y) + 0.5) / Double(height)
            // バッファ → 縦向き: ox = 1 − by, oy = bx
            let oriented = Vec2((1 - by) * imageSize.x, bx * imageSize.y)
            values[y * width + x] = depthAt(oriented)
        }
    }
    return DepthMap(width: width, height: height, values: values)
}

final class DepthTests: XCTestCase {
    func testOrientationMapping() {
        // バッファの左上の画素だけ 1.0、それ以外は 2.0
        var values = [Float](repeating: 2, count: 4 * 3)
        values[0] = 1
        let map = DepthMap(width: 4, height: 3, values: values)
        // バッファの左上 = 縦向き画像の右上
        XCTAssertEqual(map.depth(atOrientedNormalized: Vec2(0.95, 0.05)), 1)
        XCTAssertEqual(map.depth(atOrientedNormalized: Vec2(0.05, 0.05)), 2)
        // 範囲外は nil
        XCTAssertNil(map.depth(atOrientedNormalized: Vec2(1.5, 0.5)))
    }

    func testInvalidDepthIsIgnored() {
        let map = DepthMap(width: 2, height: 1, values: [0, .nan])
        XCTAssertNil(map.depth(atOrientedNormalized: Vec2(0.5, 0.25)))
        XCTAssertNil(map.medianDepth(atOrientedNormalized: Vec2(0.5, 0.25)))
    }

    /// 空中で指を止めた(面まで下りていない)タップは、LiDAR モードでは入力されない
    func testLiDARRejectsAirTap() throws {
        let (left, right) = standardHands()
        let flat = makeDepthMap { _ in 0.47 }

        func calibratedEngine() -> KeyboardEngine {
            var settings = KeyboardSettings()
            settings.useLiDAR = true
            let engine = KeyboardEngine(settings: settings)
            engine.startCalibration()
            var t = 0.0
            while engine.calibration == nil, t < 3 {
                var frame = makeFrame(time: t, hands: [left, right])
                frame.depthMap = flat
                _ = engine.process(frame)
                t += 1.0 / 30
            }
            return engine
        }

        func tap(engine: KeyboardEngine, lifted: Bool) -> [TapResult] {
            var results: [TapResult] = []
            var t = 10.0
            while t < 11 {
                let moved = left.moving(.index, by: TapDetectorTests.tapScript(start: 10.3)(t))
                var frame = makeFrame(time: t, hands: [moved, right])
                let tipImage = moved.imagePoint(moved.local[.indexTip]!)
                // lifted のときは、人差し指の先の周りだけ 3cm カメラに近い(=持ち上がっている)
                frame.depthMap = lifted
                    ? makeDepthMap { p in p.distance(to: tipImage) < 45 ? 0.44 : 0.47 }
                    : flat
                results += engine.process(frame).taps
                t += 1.0 / 60
            }
            return results
        }

        let engine = calibratedEngine()
        XCTAssertNotNil(engine.calibration?.restRelativeDepths?[FingerID(chirality: .left, finger: .index)])

        let touching = tap(engine: engine, lifted: false)
        XCTAssertEqual(touching.map { $0.key?.label }, ["F"])

        let air = tap(engine: calibratedEngine(), lifted: true)
        XCTAssertEqual(air.count, 1)
        XCTAssertNil(air.first?.key)
        XCTAssertEqual(air.first?.heightAboveSurface ?? 0, 0.03, accuracy: 0.005)
    }
}
