import XCTest
@testable import ARKeyboardCore

final class WordBeamTests: XCTestCase {
    func key(_ c: String) -> Key {
        Key(id: c, label: c.uppercased(), output: c, hand: .left, finger: .index, row: 0,
            isInnerColumn: false, center: .zero, size: Vec2(0.2, 0.2))
    }

    func candidates(_ pairs: [(String, Double)]) -> [KeyCandidate] {
        // logSpatial に確率の対数を入れる(位置だけで見た確からしさ)
        pairs.map { KeyCandidate(key: key($0.0), probability: $0.1, logSpatial: log($0.1), logLanguage: 0) }
    }

    func testLexiconFixesMiddleLetter() throws {
        let english = try RepoFiles.corpus("english")
        let model = CharNGramModel(text: english, order: 5)
        let decoder = WordBeamDecoder()
        decoder.languageModel = { c, h in model.probability(of: c, after: h) }
        decoder.lexicon = Lexicon(text: english)
        // 位置だけなら t, g, e(g の方がやや近い)
        let steps = [
            candidates([("t", 0.9), ("r", 0.1)]),
            candidates([("g", 0.55), ("h", 0.45)]),
            candidates([("e", 0.9), ("w", 0.1)]),
        ]
        XCTAssertEqual(decoder.decode(steps: steps, context: "i saw "), "the")
        // 言語モデルも辞書も無ければ、位置だけで tge
        let plain = WordBeamDecoder()
        XCTAssertEqual(plain.decode(steps: steps, context: "i saw "), "tge")
    }

    func testLexicon() {
        let lexicon = Lexicon(text: "the cat sat.")
        XCTAssertTrue(lexicon.isWord("cat"))
        XCTAssertTrue(lexicon.isPrefix("ca"))
        XCTAssertFalse(lexicon.isPrefix("cx"))
    }

    /// エンジン経由: 単語単位のデコードがオンなら、書き換えの指示(wordRewrite)が出る
    func testEngineEmitsRewrite() throws {
        let (left, right) = standardHands()
        var settings = KeyboardSettings()
        settings.features.wordDecoder = true
        let engine = KeyboardEngine(settings: settings)
        engine.setLanguageCorpora(english: try RepoFiles.corpus("english"), romaji: nil)
        engine.setCalibration(CalibrationResult(
            left: try XCTUnwrap(Calibrator.makeCalibration(from: left.observation(), chirality: .left, config: .init())),
            right: try XCTUnwrap(Calibrator.makeCalibration(from: right.observation(), chirality: .right, config: .init())),
            createdAt: Date()))
        var results: [TapResult] = []
        var t = 0.0
        while t <= 1.0 {
            let moved = left.moving(.index, by: TapDetectorTests.tapScript(start: 0.3, depth: 0.1)(t))
            results += engine.process(makeFrame(time: t, hands: [moved, right])).taps
            t += 1.0 / 60
        }
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.wordRewrite, "f")
        XCTAssertEqual(results.first?.wordReplaceCount, 0)
    }
}
