import XCTest
@testable import ARKeyboardCore

/// リポジトリ内のファイルの場所(このテストファイルの位置から求める)
enum RepoFiles {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // ARKeyboardCoreTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // リポジトリのルート

    static func corpus(_ name: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent("ARKeyboard/Resources/Corpus/corpus_\(name).txt"), encoding: .utf8)
    }

    static func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: root.appendingPathComponent("Tests/ARKeyboardCoreTests/Fixtures/\(name)"))
    }
}

final class LanguageModelTests: XCTestCase {
    func testProbabilitiesSumToOne() throws {
        let model = CharNGramModel(text: try RepoFiles.corpus("english"), order: 5)
        for context in ["", "th", "hello wor", "qqqq"] {
            let sum = CharNGramModel.vocabulary.reduce(0.0) { $0 + model.probability(of: $1, after: context) }
            XCTAssertEqual(sum, 1, accuracy: 1e-9, context)
        }
    }

    func testContextHelps() throws {
        let model = CharNGramModel(text: try RepoFiles.corpus("english"), order: 5)
        XCTAssertGreaterThan(model.probability(of: "u", after: "the q"), 0.9)
        XCTAssertGreaterThan(model.probability(of: "h", after: "t"), model.probability(of: "q", after: "t"))
        let romaji = CharNGramModel(text: try RepoFiles.corpus("romaji"), order: 5)
        XCTAssertGreaterThan(romaji.probability(of: "u", after: "arigato"), 0.5)
    }

    /// Python 版(tools/lm/ngram.py)と同じ値になること(ゴールデンテスト)
    func testMatchesPythonGolden() throws {
        struct Case: Decodable { let corpus: String; let order: Int; let context: String; let char: String; let p: Double }
        let cases = try JSONDecoder().decode([Case].self, from: try RepoFiles.fixture("lm_golden.json"))
        XCTAssertGreaterThan(cases.count, 1000)
        var models: [String: CharNGramModel] = [:]
        for c in cases {
            let key = "\(c.corpus)-\(c.order)"
            if models[key] == nil { models[key] = CharNGramModel(text: try RepoFiles.corpus(c.corpus), order: c.order) }
            let p = models[key]!.probability(of: Character(c.char), after: c.context)
            XCTAssertEqual(p, c.p, accuracy: 1e-12, "\(key) '\(c.context)' → '\(c.char)'")
        }
    }
}

/// オンセット検出の Python 版(tools/eval/onset.py)と同じ結果になること(ゴールデンテスト)
final class OnsetGoldenTests: XCTestCase {
    func testMatchesPythonGolden() throws {
        struct Golden: Decodable {
            struct Onset: Decodable { let time: Double; let strength: Double }
            let inputs: [[Double]]
            let onsets: [Onset]
            let thresholds: [Double]
        }
        let golden = try JSONDecoder().decode(Golden.self, from: try RepoFiles.fixture("onset_golden.json"))
        let detector = OnsetDetector(source: .audio)
        var onsets: [OnsetEvent] = []
        for (i, pair) in golden.inputs.enumerated() {
            if let e = detector.process(value: pair[1], time: pair[0]) { onsets.append(e) }
            XCTAssertEqual(detector.lastThreshold, golden.thresholds[i], accuracy: 1e-12)
        }
        XCTAssertEqual(onsets.count, golden.onsets.count)
        XCTAssertGreaterThan(onsets.count, 3)
        for (a, b) in zip(onsets, golden.onsets) {
            XCTAssertEqual(a.time, b.time, accuracy: 1e-12)
            XCTAssertEqual(a.strength, b.strength, accuracy: 1e-12)
        }
    }
}

/// レベルB の学習モデル: Python(numpy)で計算した出力と、Swift の DenseNetwork の出力が一致すること
final class LevelBGoldenTests: XCTestCase {
    func testDenseNetworkMatchesPython() throws {
        struct Golden: Decodable {
            let model: DenseNetwork
            let inputs: [[Double]]
            let outputs: [[Double]]
        }
        let golden = try JSONDecoder().decode(Golden.self, from: try RepoFiles.fixture("levelb_golden.json"))
        XCTAssertEqual(golden.inputs.first?.count, TapFeatures.count)
        for (input, expected) in zip(golden.inputs, golden.outputs) {
            let output = golden.model.forward(input)
            XCTAssertEqual(output.count, 3)
            for (a, b) in zip(output, expected) {
                XCTAssertEqual(a, b, accuracy: 1e-9)
            }
        }
    }
}
