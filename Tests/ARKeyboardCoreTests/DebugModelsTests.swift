import XCTest
@testable import ARKeyboardCore

final class DebugModelsTests: XCTestCase {
    func testFPSCounter() {
        var counter = FPSCounter()
        var fps = 0.0
        var t = 0.0
        while t < 3 {
            fps = counter.tick(at: t)
            t += 1.0 / 30
        }
        XCTAssertEqual(fps, 30, accuracy: 0.5)
    }

    func testTapLogSummary() {
        let event = TapEvent(finger: FingerID(chirality: .right, finger: .index), timestamp: 1,
                             tipPosition: .zero, peakSpeed: 2.345, travel: 0.1)
        let entry = TapLogEntry(id: 1, result: TapResult(event: event, key: nil, note: "キーの範囲外"))
        XCTAssertTrue(entry.summary.contains("右手の人差し指"))
        XCTAssertTrue(entry.summary.contains("キーの範囲外"))
        XCTAssertTrue(entry.summary.contains("2.35") || entry.summary.contains("2.34"))
    }
}

final class TrackerStatsTests: XCTestCase {
    func testStats() {
        var acc = TrackerStatsAccumulator()
        let (left, right) = standardHands()
        var rng = SplitMix64(seed: 3)
        for i in 0..<60 {
            var frame = makeFrame(time: Double(i) / 30, hands: i % 4 == 0 ? [left] : [left, right])
            frame = Replayer.addNoise(to: frame, sigma: 0.01, rng: &rng)
            frame.processingTime = 0.02
            let engine = KeyboardEngine()
            acc.add(frame, hands: engine.assignHands(frame.hands))
        }
        XCTAssertEqual(acc.stats.fps, 30, accuracy: 1)
        XCTAssertEqual(acc.stats.processingMs, 20, accuracy: 1e-6)
        XCTAssertEqual(acc.stats.twoHandRate, 0.75, accuracy: 0.01)
        XCTAssertGreaterThan(acc.stats.jitter, 0)
        XCTAssertLessThan(acc.stats.jitter, 0.05)
    }
}
