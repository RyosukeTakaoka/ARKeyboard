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
