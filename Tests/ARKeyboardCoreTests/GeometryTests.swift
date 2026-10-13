import XCTest
@testable import ARKeyboardCore

/// ベクトル計算と座標変換のテスト
final class GeometryTests: XCTestCase {
    func testVectorBasics() {
        let a = Vec2(3, 4)
        XCTAssertEqual(a.length, 5, accuracy: 1e-9)
        XCTAssertEqual(a.dot(Vec2(1, 0)), 3, accuracy: 1e-9)
        XCTAssertEqual(Vec2(1, 0).cross(Vec2(0, 1)), 1, accuracy: 1e-9)
        XCTAssertEqual(Vec2(1, 0).perpendicular, Vec2(0, 1))
        XCTAssertNil(Vec2.zero.normalized)
        XCTAssertEqual(Vec2.average([Vec2(0, 0), Vec2(2, 4)]), Vec2(1, 2))
    }

    func testAspectFillConversion() {
        // 縦長の画像 720x1280 を 393x852 の画面に aspectFill で表示する
        let c = CoordinateConverter(imageSize: Vec2(720, 1280), viewSize: Vec2(393, 852))
        // 高さ方向の拡大率の方が大きい → 高さがぴったり、左右がはみ出す
        XCTAssertEqual(c.scale, 852.0 / 1280.0, accuracy: 1e-9)
        // 画像の中心は画面の中心に来る
        let center = c.viewPoint(fromImage: Vec2(360, 640))
        XCTAssertEqual(center.x, 393 / 2, accuracy: 1e-9)
        XCTAssertEqual(center.y, 852 / 2, accuracy: 1e-9)
        // 画像の上端は画面の上端に来る
        XCTAssertEqual(c.viewPoint(fromImage: Vec2(360, 0)).y, 0, accuracy: 1e-9)
        // 逆変換で元に戻る
        let p = Vec2(100, 200)
        let back = c.imagePoint(fromView: c.viewPoint(fromImage: p))
        XCTAssertEqual(back.x, p.x, accuracy: 1e-9)
        XCTAssertEqual(back.y, p.y, accuracy: 1e-9)
    }
}
