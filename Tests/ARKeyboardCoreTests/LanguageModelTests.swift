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
