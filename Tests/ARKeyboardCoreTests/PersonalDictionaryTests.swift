import XCTest
@testable import ARKeyboardCore

final class PersonalDictionaryTests: XCTestCase {
    func testLearnsWordsAtDelimiters() {
        var dictionary = PersonalDictionary()
        var text = ""
        func type(_ s: String) {
            for c in s {
                let old = text
                text.append(c)
                dictionary.learn(old: old, new: text)
            }
        }
        type("hello zorbix ")
        XCTAssertEqual(dictionary.text, "hello zorbix ")
        type("a ")  // 1文字の単語は覚えない
        XCTAssertEqual(dictionary.text, "hello zorbix ")
        type("ぞるびっくす。")
        XCTAssertEqual(dictionary.kanaText, "ぞるびっくす。")
        XCTAssertEqual(dictionary.wordCount, 3)
        // 削除(文字が減る変化)では覚えない
        XCTAssertFalse(dictionary.learn(old: "abc ", new: "abc"))
        let version = dictionary.version
        dictionary.reset()
        XCTAssertTrue(dictionary.isEmpty)
        XCTAssertGreaterThan(dictionary.version, version)
    }

    /// 個人辞書の単語は、元の言語モデルでは出にくい綴りでも確率が上がる。見たことのない文脈では元のまま
    func testPersonalModelRaisesUserWords() throws {
        let corpus = try String(contentsOf: RepoFiles.root.appendingPathComponent("ARKeyboard/Resources/Corpus/corpus_english.txt"),
                                encoding: .utf8)
        let base = CharNGramModel(text: corpus, order: 5)
        let personal = CharNGramModel(text: String(repeating: "zorbix ", count: 5), order: 5)
        let mixed = PersonalLanguageModel(base: { c, h in base.probability(of: c, after: h) }, personal: personal, weight: 0.3)
        XCTAssertGreaterThan(mixed.probability(of: "b", after: "zor"), base.probability(of: "b", after: "zor") * 2)
        XCTAssertEqual(mixed.probability(of: "e", after: "th"), base.probability(of: "e", after: "th"), accuracy: 1e-12)
        // 確率の合計は 1 のまま
        let sum = CharNGramModel.vocabulary.reduce(0.0) { $0 + mixed.probability(of: $1, after: "zor") }
        XCTAssertEqual(sum, 1, accuracy: 1e-9)
    }

    /// エンジン経由: 個人辞書を入れると、フリックの仮名の言語モデルにも混ざる(オフなら混ざらない)
    func testEngineUsesPersonalKanaModel() throws {
        let engine = KeyboardEngine(settings: KeyboardSettings())
        engine.setKanaCorpus("きょうはいいてんきです。")
        var dictionary = PersonalDictionary()
        dictionary.kanaText = String(repeating: "ぞるびっくす。", count: 5)
        engine.setPersonalDictionary(dictionary)
        let withPersonal = try XCTUnwrap(engine.flickEngine.languageModel)("び", "ぞる")
        engine.settings.features.personalDictionary = false
        engine.setPersonalDictionary(dictionary)
        let without = try XCTUnwrap(engine.flickEngine.languageModel)("び", "ぞる")
        XCTAssertGreaterThan(withPersonal, without * 2)
    }
}
