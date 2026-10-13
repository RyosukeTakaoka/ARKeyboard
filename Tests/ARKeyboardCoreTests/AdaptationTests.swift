import XCTest
@testable import ARKeyboardCore

final class AdaptationTests: XCTestCase {
    let finger = FingerID(chirality: .left, finger: .index)
    let key = Key(id: "left-F", label: "F", output: "f", hand: .left, finger: .index, row: 0,
                  isInnerColumn: false, center: Vec2(1, 1), size: Vec2(0.2, 0.2))
    let gKey = Key(id: "left-G", label: "G", output: "g", hand: .left, finger: .index, row: 0,
                   isInnerColumn: true, center: Vec2(1.2, 1), size: Vec2(0.2, 0.2))

    /// いつも右に 0.1(キーの半分)ずれて押す人 → たくさん押すと、ずれが 0.5 キーに近づく
    func testLearnsConsistentOffset() throws {
        let a = PersonalAdaptation()
        for _ in 0..<200 {
            a.recordTap(finger: finger, key: key, location: key.center + Vec2(0.1, 0), posterior: 0.99)
        }
        let e = try XCTUnwrap(a.estimate(finger: finger, keyID: key.id, priorSigma: 0.3))
        XCTAssertGreaterThan(e.offset.x, 0.4)
        XCTAssertLessThanOrEqual(e.offset.x, 0.5 + 1e-9)
        XCTAssertEqual(e.offset.y, 0, accuracy: 1e-9)
    }

    /// データが少ないうちは、ずれは小さく見積もられる(縮小推定)
    func testShrinksWithFewSamples() throws {
        let a = PersonalAdaptation()
        for _ in 0..<(3 + a.config.confirmAfter) {
            a.recordTap(finger: finger, key: key, location: key.center + Vec2(0.1, 0), posterior: 0.99)
        }
        let e = try XCTUnwrap(a.estimate(finger: finger, keyID: key.id, priorSigma: 0.3))
        // 生のずれは 0.5 キーだが、3回分だけなので 0.2 キー未満に控えめに見積もる
        XCTAssertLessThan(e.offset.x, 0.2)
        XCTAssertGreaterThan(e.offset.x, 0)
    }

    /// ずれの上限
    func testCapsOffset() throws {
        let a = PersonalAdaptation()
        for _ in 0..<300 {
            a.recordTap(finger: finger, key: key, location: key.center + Vec2(0.5, 0), posterior: 0.99)
        }
        let e = try XCTUnwrap(a.estimate(finger: finger, keyID: key.id, priorSigma: 0.3))
        XCTAssertEqual(e.offset.length, a.config.maxOffset, accuracy: 1e-9)
    }

    /// 確信度の低いタップは学習に使わない
    func testIgnoresLowConfidence() {
        let a = PersonalAdaptation()
        for _ in 0..<50 {
            a.recordTap(finger: finger, key: key, location: key.center + Vec2(0.1, 0), posterior: 0.5)
        }
        XCTAssertEqual(a.totalSamples, 0)
    }

    /// 削除して打ち直した: 消したタップの位置は「打ち直したキー」を狙っていた、とみなす
    func testBackspaceCorrectionTeachesIntendedKey() throws {
        let a = PersonalAdaptation()
        // G を狙ったが F の右端を押して F になった → 削除 → G を打ち直した
        let pressed = key.center + Vec2(0.09, 0)
        a.recordTap(finger: finger, key: key, location: pressed, posterior: 0.95)
        a.noteBackspace()
        a.recordTap(finger: finger, key: gKey, location: gKey.center, posterior: 0.99)
        // G のずれとして、左へ 0.55 キー(= (0.09 - 0.2) / 0.2)のデータが1つ入った
        let s = try XCTUnwrap(a.stats[PersonalAdaptation.key(finger: finger, keyID: gKey.id)])
        XCTAssertEqual(s.n, 1)
        XCTAssertEqual(s.sum.x, -0.55, accuracy: 1e-9)
    }

    /// 保存して読み込める
    func testCodableRoundTrip() throws {
        let a = PersonalAdaptation()
        for _ in 0..<20 {
            a.recordTap(finger: finger, key: key, location: key.center + Vec2(0.05, 0.02), posterior: 0.99)
        }
        let data = try JSONEncoder().encode(a)
        let b = try XCTUnwrap(PersonalAdaptation.load(from: data))
        XCTAssertEqual(b.totalSamples, a.totalSamples)
        XCTAssertEqual(b.estimate(finger: finger, keyID: key.id, priorSigma: 0.3)?.offset,
                       a.estimate(finger: finger, keyID: key.id, priorSigma: 0.3)?.offset)
    }

    /// 空間タッチモデルに反映すると、ずれた方向の確率が上がる
    func testLearnedGaussianShiftsDecoder() {
        let a = PersonalAdaptation()
        for _ in 0..<200 {
            a.recordTap(finger: finger, key: gKey, location: gKey.center - Vec2(0.07, 0), posterior: 0.99)
        }
        let decoder = TapDecoder()
        decoder.config.anchorFraction = 0
        let point = Vec2.lerp(key.center, gKey.center, 0.45)  // F 寄りの真ん中
        let before = decoder.decode(location: point, measurementCovariance: .isotropic(sigma: 0.01), finger: finger,
                                    keys: [key, gKey], context: "", interval: nil, restrictToFinger: true,
                                    useLanguageModel: false)
        XCTAssertEqual(before.best?.label, "F")
        decoder.spatial.setLearned(a.learnedGaussians(keys: [key, gKey], priorSigma: 0.3))
        let after = decoder.decode(location: point, measurementCovariance: .isotropic(sigma: 0.01), finger: finger,
                                   keys: [key, gKey], context: "", interval: nil, restrictToFinger: true,
                                   useLanguageModel: false)
        XCTAssertEqual(after.best?.label, "G")
    }
}
