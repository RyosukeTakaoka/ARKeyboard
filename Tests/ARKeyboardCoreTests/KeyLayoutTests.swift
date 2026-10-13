import XCTest
@testable import ARKeyboardCore

final class KeyLayoutTests: XCTestCase {
    private func calibration(_ chirality: Chirality) throws -> HandCalibration {
        let hand = SyntheticHand(chirality: chirality)
        return try XCTUnwrap(Calibrator.makeCalibration(from: hand.observation(), chirality: chirality,
                                                        config: Calibrator.Config()))
    }

    func testKeyCounts() throws {
        XCTAssertEqual(KeyLayout.makeKeys(for: try calibration(.left), keyScale: 1).count, 15 + 1)
        XCTAssertEqual(KeyLayout.makeKeys(for: try calibration(.right), keyScale: 1).count, 14 + 1)
    }

    /// 指を動かした先のキーが正しく選ばれること
    func testNearestKeyFollowsFingerMovement() throws {
        for chirality in Chirality.allCases {
            let cal = try calibration(chirality)
            let keys = KeyLayout.makeKeys(for: cal, keyScale: 1)
            let index = try XCTUnwrap(cal.homeTips[.index])
            func label(_ p: Vec2, _ finger: Finger = .index) -> String? {
                KeyLayout.nearestKey(to: p, finger: finger, in: keys, restrictToFinger: true, maxDistance: 1.3)?.key.label
            }
            let left = chirality == .left
            // ホーム位置
            XCTAssertEqual(label(index), left ? "F" : "J")
            // 前(奥)に1行
            XCTAssertEqual(label(index + Vec2(0, cal.rowPitch)), left ? "R" : "U")
            // 手前に1行
            XCTAssertEqual(label(index - Vec2(0, cal.rowPitch)), left ? "V" : "M")
            // 親指側(キーボードの中央側)に1キー
            XCTAssertEqual(label(index + Vec2(cal.keyPitch, 0)), left ? "G" : "H")
            // 親指側 + 奥
            XCTAssertEqual(label(index + Vec2(cal.keyPitch, cal.rowPitch)), left ? "T" : "Y")
            // 小指のホーム
            XCTAssertEqual(label(try XCTUnwrap(cal.homeTips[.little]), .little), left ? "A" : ";")
            // 親指はスペースだけ
            XCTAssertEqual(label(try XCTUnwrap(cal.homeTips[.thumb]), .thumb), "space")
            // 遠すぎる点はどのキーでもない
            XCTAssertNil(label(index + Vec2(0, cal.rowPitch * 5)))
        }
    }

    /// 担当キーに限定すると、中指は人差し指の列(R)の上に来ても E D C のどれかになる
    func testRestrictToFinger() throws {
        let cal = try calibration(.left)
        let keys = KeyLayout.makeKeys(for: cal, keyScale: 1)
        let rKey = try XCTUnwrap(keys.first { $0.label == "R" })
        let restricted = KeyLayout.nearestKey(to: rKey.center, finger: .middle, in: keys,
                                              restrictToFinger: true, maxDistance: 3)?.key.label
        XCTAssertEqual(restricted, "E")
        let free = KeyLayout.nearestKey(to: rKey.center, finger: .middle, in: keys,
                                        restrictToFinger: false, maxDistance: 3)?.key.label
        XCTAssertEqual(free, "R")
    }

    /// エンジン経由: キャリブレーション後、指先の下のキーが光る
    func testEngineHoverAfterCalibration() throws {
        let (left, right) = standardHands()
        let engine = KeyboardEngine()
        engine.setCalibration(CalibrationResult(
            left: try XCTUnwrap(Calibrator.makeCalibration(from: left.observation(), chirality: .left, config: .init())),
            right: try XCTUnwrap(Calibrator.makeCalibration(from: right.observation(), chirality: .right, config: .init())),
            createdAt: Date()))
        let output = engine.process(makeFrame(time: 0, hands: [left, right]))
        for id in ["left-A", "left-S", "left-D", "left-F", "left-space", "right-J", "right-K", "right-L", "right-;", "right-space"] {
            XCTAssertTrue(output.hoveredKeyIDs.contains(id), id)
        }
        XCTAssertEqual(output.hoveredKeyIDs.count, 10)

        // 「面に固定」でも、手を動かしていなければ同じ結果
        engine.settings.anchor = .fixed
        let fixedOutput = engine.process(makeFrame(time: 0.03, hands: [left, right]))
        XCTAssertEqual(fixedOutput.hoveredKeyIDs, output.hoveredKeyIDs)

        // 「面に固定」で左手全体を親指側へ1キー分ずらすと、F → G に変わる
        var shifted = left
        shifted.origin.x += engine.calibration!.left.keyPitch * left.scale
        let shiftedOutput = engine.process(makeFrame(time: 0.06, hands: [shifted, right]))
        XCTAssertTrue(shiftedOutput.hoveredKeyIDs.contains("left-G"))
        XCTAssertFalse(shiftedOutput.hoveredKeyIDs.contains("left-F"))
    }
}
