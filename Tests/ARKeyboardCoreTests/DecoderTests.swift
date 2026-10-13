import XCTest
@testable import ARKeyboardCore

final class DecoderTests: XCTestCase {
    var leftKeys: [Key] = []
    var rightKeys: [Key] = []
    var decoder = TapDecoder()
    var english: CharNGramModel!

    override func setUpWithError() throws {
        let (left, right) = standardHands()
        let leftCal = try XCTUnwrap(Calibrator.makeCalibration(from: left.observation(), chirality: .left, config: .init()))
        let rightCal = try XCTUnwrap(Calibrator.makeCalibration(from: right.observation(), chirality: .right, config: .init()))
        leftKeys = KeyLayout.makeKeys(for: leftCal, keyScale: 1)
        rightKeys = KeyLayout.makeKeys(for: rightCal, keyScale: 1)
        english = CharNGramModel(text: try RepoFiles.corpus("english"), order: 5)
        decoder = TapDecoder()
        let model = english!
        decoder.languageModel = { c, h in model.probability(of: c, after: h) }
    }

    func key(_ label: String, in keys: [Key]) -> Key { keys.first { $0.label == label }! }

    let leftIndex = FingerID(chirality: .left, finger: .index)
    let noise = Covariance2.isotropic(sigma: 0.03)

    /// F と G のちょうど真ん中を押したとき、文脈「the do」なら G(dog)になる
    func testLanguageModelResolvesAmbiguity() {
        let f = key("F", in: leftKeys), g = key("G", in: leftKeys)
        let middle = Vec2.lerp(f.center, g.center, 0.5)
        let withLM = decoder.decode(location: middle, measurementCovariance: noise, finger: leftIndex, keys: leftKeys,
                                    context: "the do", interval: nil, restrictToFinger: true, useLanguageModel: true)
        XCTAssertEqual(withLM.best?.label, "G")
        // 文脈「i am typin」なら G(typing)、文脈「the le」なら F(left)
        let left = decoder.decode(location: middle, measurementCovariance: noise, finger: leftIndex, keys: leftKeys,
                                  context: "on the le", interval: nil, restrictToFinger: true, useLanguageModel: true)
        XCTAssertEqual(left.best?.label, "F")
        // 確率の合計は 1
        XCTAssertEqual(withLM.candidates.reduce(0) { $0 + $1.probability }, 1, accuracy: 1e-9)
        // 担当キー(R T F G V B)だけが候補
        XCTAssertEqual(Set(withLM.candidates.map(\.key.label)), ["R", "T", "F", "G", "V", "B"])
    }

    /// キーの真ん中(アンカー)を押したら、文脈がどうであってもそのキー
    func testAnchorAlwaysWins() {
        let f = key("F", in: leftKeys)
        let result = decoder.decode(location: f.center, measurementCovariance: noise, finger: leftIndex, keys: leftKeys,
                                    context: "the do", interval: nil, restrictToFinger: true, useLanguageModel: true)
        XCTAssertEqual(result.best?.label, "F")
        XCTAssertTrue(result.anchored)
    }

    /// 言語モデルの重みを強くしすぎても、アンカーを切っていなければキーの中央は守られる。
    /// アンカーを切ると、言語モデルが強いとき中央を押しても別のキーになりうる(Gunawardana らの指摘)
    func testWithoutAnchorStrongLMCanOverride() {
        decoder.config.anchorFraction = 0
        decoder.config.lmWeight = 6
        let f = key("F", in: leftKeys)
        let result = decoder.decode(location: f.center, measurementCovariance: noise, finger: leftIndex, keys: leftKeys,
                                    context: "the do", interval: nil, restrictToFinger: true, useLanguageModel: true)
        XCTAssertEqual(result.best?.label, "G")
        XCTAssertFalse(result.anchored)
    }

    func testSpeedAdaptation() {
        XCTAssertEqual(decoder.speed(forInterval: 0.1), 1)
        XCTAssertEqual(decoder.speed(forInterval: 1.0), 0)
        XCTAssertEqual(decoder.speed(forInterval: nil), 0)
        XCTAssertEqual(decoder.speed(forInterval: 0.39), 0.5, accuracy: 1e-9)
        // 速いと言語モデルが強く効く: 曖昧な位置で G の確率が上がる
        decoder.config.anchorFraction = 0
        let f = key("F", in: leftKeys), g = key("G", in: leftKeys)
        let p = Vec2.lerp(f.center, g.center, 0.4)
        func probG(_ interval: Double) -> Double {
            decoder.decode(location: p, measurementCovariance: noise, finger: leftIndex, keys: leftKeys,
                           context: "the do", interval: interval, restrictToFinger: true, useLanguageModel: true)
                .candidates.first { $0.key.label == "G" }?.probability ?? 0
        }
        XCTAssertGreaterThan(probG(0.1), probG(1.0))
    }

    /// 当たり判定の地図: 「the q」の後は U の領域が広がる(Apple 型の動的な当たり判定を事前確率で再現)
    func testHitMapGrowsWithContext() throws {
        let neutral = try XCTUnwrap(decoder.hitMap(keys: rightKeys, context: "zzzz", useLanguageModel: true))
        let afterQ = try XCTUnwrap(decoder.hitMap(keys: rightKeys, context: "the q", useLanguageModel: true))
        let neutralU = neutral.areaByKey["right-U"] ?? 0
        let qU = afterQ.areaByKey["right-U"] ?? 0
        XCTAssertGreaterThan(qU, neutralU)
        // アンカーのおかげで、I のキーの中央はまだ I のまま
        let i = key("I", in: rightKeys)
        let nearestCell = afterQ.cells.min { $0.center.distance(to: i.center) < $1.center.distance(to: i.center) }
        XCTAssertEqual(nearestCell?.keyID, "right-I")
    }

    /// エンジン経由: 文脈と言語モデルで、曖昧なタップのキーが決まる
    func testEngineUsesDecoder() throws {
        let (left, right) = standardHands()
        let engine = KeyboardEngine()
        engine.setLanguageCorpora(english: try RepoFiles.corpus("english"), romaji: nil)
        engine.setCalibration(CalibrationResult(
            left: try XCTUnwrap(Calibrator.makeCalibration(from: left.observation(), chirality: .left, config: .init())),
            right: try XCTUnwrap(Calibrator.makeCalibration(from: right.observation(), chirality: .right, config: .init())),
            createdAt: Date()))
        engine.context = "the do"
        let cal = try XCTUnwrap(engine.calibration?.left)
        // 人差し指を F と G の真ん中(親指側に半キー)へ置いてからタップ
        let shift = Vec2(cal.keyPitch * 0.5, 0)
        var results: [TapResult] = []
        var t = 0.0
        while t <= 1.0 {
            let moved = left.moving(.index, by: shift + TapDetectorTests.tapScript(start: 0.3, depth: 0.1)(t))
            results += engine.process(makeFrame(time: t, hands: [moved, right])).taps
            t += 1.0 / 60
        }
        XCTAssertEqual(results.map { $0.key?.label }, ["G"])
        XCTAssertNotNil(results.first?.decode)

        // デコーダーをオフにすると、いちばん近いキー(同点なら内側の列より F)
        engine.settings.features.decoder = false
        var plain: [TapResult] = []
        t = 2.0
        while t <= 3.0 {
            let moved = left.moving(.index, by: shift + TapDetectorTests.tapScript(start: 2.3, depth: 0.1)(t))
            plain += engine.process(makeFrame(time: t, hands: [moved, right])).taps
            t += 1.0 / 60
        }
        XCTAssertEqual(plain.map { $0.key?.label }, ["F"])
    }
}
