import XCTest
@testable import ARKeyboardCore

final class KanaTests: XCTestCase {
    func testLayoutPositions() throws {
        let na = try XCTUnwrap(FlickLayout.position(of: "な"))
        XCTAssertEqual(na.row, 1); XCTAssertEqual(na.column, 1); XCTAssertEqual(na.direction, .tap)
        let ni = try XCTUnwrap(FlickLayout.position(of: "に"))
        XCTAssertEqual(ni.direction, .left)
        let o = try XCTUnwrap(FlickLayout.position(of: "お"))
        XCTAssertEqual(o.direction, .down)
        // 濁点付きは元の文字の位置
        let gi = try XCTUnwrap(FlickLayout.position(of: "ぎ"))
        XCTAssertEqual(gi.row, 0); XCTAssertEqual(gi.column, 1); XCTAssertEqual(gi.direction, .left)
    }

    func testModifierCycles() {
        XCTAssertEqual(KanaModifier.cycle("か"), "が")
        XCTAssertEqual(KanaModifier.cycle("が"), "か")
        XCTAssertEqual(KanaModifier.cycle("は"), "ば")
        XCTAssertEqual(KanaModifier.cycle("ば"), "ぱ")
        XCTAssertEqual(KanaModifier.cycle("ぱ"), "は")
        XCTAssertEqual(KanaModifier.cycle("つ"), "っ")
        XCTAssertNil(KanaModifier.cycle("ん"))
    }

    func testKanaLanguageModel() throws {
        let text = try String(contentsOf: RepoFiles.root.appendingPathComponent("ARKeyboard/Resources/Corpus/corpus_kana.txt"),
                              encoding: .utf8)
        let model = CharNGramModel(text: text, order: 5, vocabulary: FlickLayout.kanaVocabulary)
        let sum = FlickLayout.kanaVocabulary.reduce(0.0) { $0 + model.probability(of: $1, after: "きょう") }
        XCTAssertEqual(sum, 1, accuracy: 1e-9)
        XCTAssertGreaterThan(model.probability(of: "う", after: "ありがと"), 0.5)
    }
}

final class FlickModelTests: XCTestCase {
    let config = FlickConfig()

    func testDirectionProbabilities() {
        // 右手: 手の座標の +x(親指側)は画面の左
        let left = FlickModel.directionProbabilities(displacement: Vec2(0.3, 0), hand: .right, config: config)
        XCTAssertEqual(left.max { $0.value < $1.value }?.key, .left)
        let up = FlickModel.directionProbabilities(displacement: Vec2(0, 0.3), hand: .right, config: config)
        XCTAssertEqual(up.max { $0.value < $1.value }?.key, .up)
        let right = FlickModel.directionProbabilities(displacement: Vec2(-0.3, 0.02), hand: .right, config: config)
        XCTAssertEqual(right.max { $0.value < $1.value }?.key, .right)
        let tap = FlickModel.directionProbabilities(displacement: Vec2(0.02, -0.01), hand: .right, config: config)
        XCTAssertEqual(tap.max { $0.value < $1.value }?.key, .tap)
        XCTAssertEqual(tap.values.reduce(0, +), 1, accuracy: 1e-9)
        // 左手では +x が画面の右
        let leftHandRight = FlickModel.directionProbabilities(displacement: Vec2(0.3, 0), hand: .left, config: config)
        XCTAssertEqual(leftHandRight.max { $0.value < $1.value }?.key, .right)
    }

    func flickKeys() throws -> [FlickKey] {
        let right = SyntheticHand(chirality: .right, origin: Vec2(520, 1000))
        let cal = try XCTUnwrap(Calibrator.makeCalibration(from: right.observation(), chirality: .right, config: .init()))
        return FlickModel.makeKeys(for: cal, config: config)
    }

    func testKeysAroundIndexHome() throws {
        let keys = try flickKeys()
        XCTAssertEqual(keys.count, 12)
        let na = try XCTUnwrap(keys.first { $0.definition.label == "な" })
        XCTAssertEqual(na.center.x, 0.35, accuracy: 1e-6)  // 右手の人差し指のホーム(手の座標)
        // 「あ」は上の段の左(右手なので、画面の左 = 親指側 = +x)
        let a = try XCTUnwrap(keys.first { $0.definition.label == "あ" })
        XCTAssertGreaterThan(a.center.y, na.center.y)
        XCTAssertGreaterThan(a.center.x, na.center.x)
    }

    /// 方向があいまい(上と右の間)なとき、文脈で決まる: 「ありがと」の次は「う」(あ の上)
    func testContextResolvesAmbiguousDirection() throws {
        let keys = try flickKeys()
        let a = try XCTUnwrap(keys.first { $0.definition.label == "あ" })
        let text = try String(contentsOf: RepoFiles.root.appendingPathComponent("ARKeyboard/Resources/Corpus/corpus_kana.txt"),
                              encoding: .utf8)
        let model = CharNGramModel(text: text, order: 5, vocabulary: FlickLayout.kanaVocabulary)
        // 右手で「右上」(画面の右 = −x、上 = +y)へ 45 度
        let gesture = FlickGesture(finger: FingerID(chirality: .right, finger: .index), startTime: 0, endTime: 0.1,
                                   start: a.center, displacement: Vec2(-0.2, 0.2), peakSpeed: 3)
        let withLM = FlickModel.decode(gesture: gesture, keys: keys, context: "ありがと", config: config,
                                       languageModel: { c, h in model.probability(of: c, after: h) })
        XCTAssertEqual(withLM.best?.output, "う")
        let priors = FlickModel.directionPriors(for: a, context: "ありがと", config: config,
                                                languageModel: { c, h in model.probability(of: c, after: h) })
        XCTAssertEqual(priors.max { $0.value < $1.value }?.key, .up)
    }

    func testBeamAppliesModifier() throws {
        let keys = try flickKeys()
        let ka = try XCTUnwrap(keys.first { $0.definition.label == "か" })
        let modifier = try XCTUnwrap(keys.first { $0.definition.isModifier })
        let beam = KanaBeamDecoder()
        let steps = [
            [FlickCandidate(output: "か", key: ka, direction: .tap, probability: 1, logLikelihood: 0)],
            [FlickCandidate(output: "゛", key: modifier, direction: .tap, probability: 1, logLikelihood: 0)],
        ]
        XCTAssertEqual(beam.decode(steps: steps, context: "").first, "が")
    }
}

final class FlickSegmenterTests: XCTestCase {
    let finger = FingerID(chirality: .right, finger: .index)

    func run(_ path: (Double) -> Vec2, duration: Double = 1.0) -> [FlickGesture] {
        let segmenter = FlickSegmenter()
        var gestures: [FlickGesture] = []
        var t = 0.0
        while t <= duration {
            let rel = path(t)
            if let g = segmenter.process(finger: finger, position: rel, rel: rel, time: t) { gestures.append(g) }
            t += 1.0 / 60
        }
        return gestures
    }

    func ease(_ x: Double) -> Double { let t = min(max(x, 0), 1); return t * t * (3 - 2 * t) }

    func testFastFlickIsDetected() throws {
        let gestures = run { t in Vec2(0.3 * self.ease((t - 0.3) / 0.12), 0) }
        XCTAssertEqual(gestures.count, 1)
        XCTAssertEqual(try XCTUnwrap(gestures.first).displacement.x, 0.3, accuracy: 0.03)
    }

    func testSlowRepositionIsIgnored() {
        // 0.4 手を 0.8 秒かけて動かす(キーの上への移動)
        XCTAssertTrue(run { t in Vec2(0.4 * self.ease((t - 0.1) / 0.8), 0) }.isEmpty)
    }

    /// 30fps・関節点の震えあり: 空中タップは「タップ」のまま(折り返しで切れて「下フリック」にならない)。
    /// 速さの平滑化を時間で決める修正と、止まりの継続時間(endHold)の回帰テスト
    func testAirTapAt30fpsWithJitter() throws {
        var rng = SplitMix64(seed: 7)
        let segmenter = FlickSegmenter()
        var gestures: [FlickGesture] = []
        var t = 0.0
        while t <= 1.0 {
            let x = (t - 0.4) / 0.14
            var rel = Vec2(0, x > 0 && x < 1 ? -0.15 * sin(Double.pi * x) : 0)
            rel += Vec2(rng.nextGaussian(), rng.nextGaussian()) * 0.006
            if let g = segmenter.process(finger: finger, position: rel, rel: rel, time: t) { gestures.append(g) }
            t += 1.0 / 30
        }
        XCTAssertEqual(gestures.count, 1)
        let probabilities = FlickModel.directionProbabilities(displacement: try XCTUnwrap(gestures.first).displacement,
                                                              hand: .right, config: FlickConfig())
        XCTAssertEqual(probabilities.max { $0.value < $1.value }?.key, .tap)
    }

    func testAirTapHasSmallDisplacement() throws {
        // 0.12 秒で下ろして戻す(空中のタップ)
        let gestures = run { t in
            let x = (t - 0.3) / 0.14
            return Vec2(0, x > 0 && x < 1 ? -0.15 * sin(Double.pi * x) : 0)
        }
        XCTAssertEqual(gestures.count, 1)
        XCTAssertLessThan(try XCTUnwrap(gestures.first).displacement.length, FlickConfig().tapDistance)
    }
}

final class FlickEngineTests: XCTestCase {
    /// エンジン経由: 右手の人差し指でフリックすると仮名が入力される(な = タップ、に = 左フリック)
    func testEngineFlickInput() throws {
        let (left, right) = standardHands()
        var settings = KeyboardSettings()
        settings.inputMode = .flick
        settings.flick.useLanguageModel = false
        let engine = KeyboardEngine(settings: settings)
        engine.setCalibration(CalibrationResult(
            left: try XCTUnwrap(Calibrator.makeCalibration(from: left.observation(), chirality: .left, config: .init())),
            right: try XCTUnwrap(Calibrator.makeCalibration(from: right.observation(), chirality: .right, config: .init())),
            createdAt: Date()))
        XCTAssertEqual(engine.flickEngine.keys.count, 24)
        func ease(_ x: Double) -> Double { let t = min(max(x, 0), 1); return t * t * (3 - 2 * t) }
        var flicks: [FlickResult] = []
        var t = 0.0
        while t <= 2.0 {
            var delta = Vec2.zero
            // 0.3秒: 空中タップ(下ろして戻す)= な
            let x1 = (t - 0.3) / 0.14
            if x1 > 0 && x1 < 1 { delta.y -= 0.15 * sin(Double.pi * x1) }
            // 1.0秒: 画面の左へフリック(右手なので +x)= に。その後ゆっくり戻す
            delta.x += 0.3 * ease((t - 1.0) / 0.12) * (1 - ease((t - 1.4) / 0.5))
            let output = engine.process(makeFrame(time: t, hands: [left, right.moving(.index, by: delta)]))
            flicks += output.flicks
            t += 1.0 / 60
        }
        XCTAssertEqual(flicks.map(\.output), ["な", "に"])
        XCTAssertEqual(flicks.last?.rewrite, "なに")
        XCTAssertEqual(flicks.last?.replaceCount, 1)
    }

    /// 候補の選択: 2番目の候補を選ぶと、表示中の並びがそれに置き換わり、並びは確定する
    func testSelectCandidateReplacesRun() throws {
        let engine = FlickEngine()
        let right = SyntheticHand(chirality: .right, origin: Vec2(520, 1000))
        let cal = try XCTUnwrap(Calibrator.makeCalibration(from: right.observation(), chirality: .right, config: .init()))
        let left = SyntheticHand(chirality: .left, origin: Vec2(220, 1000))
        let calLeft = try XCTUnwrap(Calibrator.makeCalibration(from: left.observation(), chirality: .left, config: .init()))
        engine.config.useLanguageModel = false
        engine.rebuildKeys(calibration: CalibrationResult(left: calLeft, right: cal, createdAt: Date()))
        let ka = try XCTUnwrap(engine.keys.first { $0.hand == .right && $0.definition.label == "か" })
        // 上と右の間(あいまい)へのフリック → 候補が2つ以上できる
        let gesture = FlickGesture(finger: FingerID(chirality: .right, finger: .index), startTime: 0, endTime: 0.1,
                                   start: ka.center, displacement: Vec2(-0.2, 0.2), peakSpeed: 3)
        let result = engine.handle(gesture, context: "")
        XCTAssertGreaterThanOrEqual(result.nBest.count, 2)
        let pick = try XCTUnwrap(engine.selectCandidate(1))
        XCTAssertEqual(pick.rewrite, result.nBest[1])
        XCTAssertEqual(pick.replaceCount, 1)
        // 確定したので、次のフリックは新しい並び(消す文字数 0)
        let next = engine.handle(gesture, context: pick.rewrite)
        XCTAssertEqual(next.replaceCount, 0)
    }

    /// 合成のフリックの記録を、アプリと同じエンジンで再生すると、ほぼ目標どおりに入力される
    func testSyntheticFlickRecordingReplays() throws {
        let text = "きょうはいいてんきですね。"
        var config = SyntheticFlickConfig(targets: SyntheticFlickGenerator.targets(from: text))
        config.audioMissRate = 0
        let recording = SyntheticFlickGenerator.generate(config)
        var options = Replayer.Options()
        options.settingsPatch = ["flick": ["useLanguageModel": false]]
        let result = Replayer(recording: recording, options: options).run()
        XCTAssertTrue(result.calibrated)
        let flicks = result.taps.filter { $0.flickDirection != nil }
        XCTAssertEqual(flicks.count, config.targets.count)
        // 文字誤り(置換)が 2 文字以下
        XCTAssertEqual(result.finalText.count, text.count)
        let errors = zip(result.finalText, text).filter { $0 != $1 }.count
        XCTAssertLessThanOrEqual(errors, 2, result.finalText)
    }
}

final class OneEuroFilterTests: XCTestCase {
    /// 止まっているときの震えは小さくなり、速く動いたら遅れずに付いていく
    func testReducesJitterAndFollowsFastMotion() {
        var rng = SplitMix64(seed: 3)
        var filter = OneEuroFilter2(minCutoff: 1.5, beta: 3)
        var rawVariance = 0.0, filteredVariance = 0.0
        var t = 0.0
        for i in 0..<60 {
            let raw = Vec2(rng.nextGaussian(), rng.nextGaussian()) * 0.01
            let out = filter.filter(raw, time: t)
            if i >= 10 {
                rawVariance += raw.dot(raw)
                filteredVariance += out.dot(out)
            }
            t += 1.0 / 30
        }
        XCTAssertLessThan(filteredVariance, rawVariance * 0.5)
        // 0.3 手を 0.1 秒で動かす: 動き終わって 0.1 秒後には、8 割以上付いてきている
        var out = Vec2.zero
        for i in 1...6 {
            let x = min(Double(i) / 3, 1) * 0.3
            out = filter.filter(Vec2(x, 0), time: t)
            t += 1.0 / 30
        }
        XCTAssertGreaterThan(out.x, 0.24)
    }
}
