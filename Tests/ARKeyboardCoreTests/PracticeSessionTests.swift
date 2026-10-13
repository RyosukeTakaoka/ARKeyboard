import XCTest
@testable import ARKeyboardCore

final class PracticeSessionTests: XCTestCase {
    func testAccuracyAndSpeed() {
        var session = PracticeSession(sentenceIndex: 0)  // "asdf jkl;"(9文字)
        XCTAssertEqual(session.target, "asdf jkl;")
        session.input("asdx", at: 10)        // 4文字目を間違える
        XCTAssertEqual(session.accuracy, 0.75, accuracy: 1e-9)
        session.backspace()                  // 消して打ち直す(間違えた記録は残る)
        session.input("f jkl;", at: 13)
        XCTAssertTrue(session.isFinished)
        XCTAssertEqual(session.totalCount, 10)
        XCTAssertEqual(session.correctCount, 9)
        // 9文字を 3秒で → 180 文字/分
        XCTAssertEqual(session.charactersPerMinute(now: 100), 180, accuracy: 1e-6)
        // 終わった後の入力は無視
        session.input("zzz", at: 14)
        XCTAssertEqual(session.totalCount, 10)
    }

    func testCharacterStates() {
        var session = PracticeSession(sentenceIndex: 0)
        session.input("ax", at: 0)
        let states = session.characterStates.map(\.state)
        XCTAssertEqual(Array(states.prefix(4)), [.correct, .wrong, .current, .pending])
    }

    func testNextWrapsAround() {
        var session = PracticeSession(sentenceIndex: PracticeSession.sentences.count - 1)
        session.input("a", at: 0)
        session.next()
        XCTAssertEqual(session.sentenceIndex, 0)
        XCTAssertEqual(session.totalCount, 0)
    }

    /// 練習のお題は、すべてこのキーボードで打てる文字だけでできている
    func testSentencesUseOnlyAvailableKeys() {
        let available = Set((KeyLayout.leftRows + KeyLayout.rightRows).joined().map { $0.lowercased() }).union([" "])
        for sentence in PracticeSession.sentences {
            for character in sentence {
                XCTAssertTrue(available.contains(String(character)), "\(character) in \(sentence)")
            }
        }
    }
}

final class CalibrationPersistenceTests: XCTestCase {
    /// キャリブレーション結果を保存(JSON)して読み戻せる
    func testCalibrationRoundTrip() throws {
        let (left, right) = standardHands()
        let result = CalibrationResult(
            left: try XCTUnwrap(Calibrator.makeCalibration(from: left.observation(), chirality: .left, config: .init())),
            right: try XCTUnwrap(Calibrator.makeCalibration(from: right.observation(), chirality: .right, config: .init())),
            createdAt: Date(timeIntervalSince1970: 1_000_000))
        let data = try JSONEncoder().encode(result)
        XCTAssertEqual(try JSONDecoder().decode(CalibrationResult.self, from: data), result)
    }
}
