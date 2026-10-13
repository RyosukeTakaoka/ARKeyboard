import XCTest
@testable import ARKeyboardCore

final class RecordingTests: XCTestCase {
    func testHandRoundTrip() {
        let hand = SyntheticHand(chirality: .left).observation()
        let restored = RecordedHand(hand).observation
        XCTAssertEqual(restored.chirality, .left)
        for (joint, point) in hand.joints {
            let p = restored.joints[joint]
            XCTAssertEqual(p?.position.x ?? 0, point.position.x, accuracy: 0.006)
            XCTAssertEqual(p?.position.y ?? 0, point.position.y, accuracy: 0.006)
            XCTAssertEqual(p?.confidence ?? 0, point.confidence, accuracy: 0.0006)
        }
    }

    func testSessionAdvancesOnTypedKey() throws {
        let task = RecordingTask(kind: .keys, targets: ["f", "j"])
        let session = RecordingSession(task: task, settings: KeyboardSettings(), calibration: nil,
                                       deskPlane: nil, device: "test", startTime: 0)
        XCTAssertEqual(session.currentTarget, "f")
        let event = TapEvent(finger: FingerID(chirality: .left, finger: .index), timestamp: 1,
                             tipPosition: .zero, peakSpeed: 2, travel: 0.1)
        // 却下されたタップでは進まない
        session.addTap(TapResult(event: event, key: nil, note: "音なし"), at: 1.1)
        XCTAssertEqual(session.currentTarget, "f")
        let key = Key(id: "left-F", label: "F", output: "f", hand: .left, finger: .index, row: 0,
                      isInnerColumn: false, center: .zero, size: Vec2(0.2, 0.2))
        session.addTap(TapResult(event: event, key: key, note: nil), at: 1.2)
        XCTAssertEqual(session.currentTarget, "j")
        session.skip(at: 2)
        XCTAssertTrue(session.isFinished)
        XCTAssertEqual(session.recording.prompts.map(\.target), ["f", "j"])
        XCTAssertEqual(session.recording.events.count, 2)
    }

    func testEncodeAndLoad() throws {
        let task = RecordingSession.makeTask(kind: .keys, count: 5, seed: 42)
        XCTAssertEqual(task.targets.count, 5)
        let session = RecordingSession(task: task, settings: KeyboardSettings.defaults(for: .desk), calibration: nil,
                                       deskPlane: nil, device: "test", startTime: 0)
        let (left, right) = standardHands()
        session.addFrame(makeFrame(time: 0.5, hands: [left, right]))
        session.addAudio(features: [AudioFeature(time: 0.5, rms: 0.1, flux: 0.02, threshold: 0.01)],
                         onsets: [OnsetEvent(source: .audio, time: 0.5, strength: 2)])
        let data = try RecordingIO.encoder().encode(session.recording)
        let loaded = try RecordingIO.load(data)
        XCTAssertEqual(loaded.frames.count, 1)
        XCTAssertEqual(loaded.frames.first?.visionFrame.hands.count, 2)
        XCTAssertEqual(loaded.audioOnsets.count, 1)
        XCTAssertEqual(loaded.settings.mode, .desk)
    }

    /// 古いファイル(設定の項目が足りない)でも読める
    func testLoadOldFileWithMissingSettings() throws {
        let session = RecordingSession(task: RecordingTask(kind: .keys, targets: ["a"]), settings: KeyboardSettings(),
                                       calibration: nil, deskPlane: nil, device: "test", startTime: 0)
        let data = try RecordingIO.encoder().encode(session.recording)
        var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var settings = try XCTUnwrap(object["settings"] as? [String: Any])
        settings.removeValue(forKey: "decoder")
        settings.removeValue(forKey: "features")
        object["settings"] = settings
        let old = try JSONSerialization.data(withJSONObject: object)
        let loaded = try RecordingIO.load(old)
        XCTAssertEqual(loaded.settings.decoder, DecoderConfig())
    }

    func testPhraseTask() {
        let task = RecordingSession.makeTask(kind: .phrases, count: 2, seed: 0)
        let text = task.targets.joined()
        XCTAssertTrue(text.hasPrefix(PracticeSession.sentences[0]))
        XCTAssertTrue(text.contains(PracticeSession.sentences[1]))
    }
}
