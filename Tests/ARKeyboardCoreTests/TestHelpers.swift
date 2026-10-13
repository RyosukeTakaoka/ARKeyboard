import Foundation
@testable import ARKeyboardCore

/// 左右そろった VisionFrame を作る
func makeFrame(time: Double, hands: [SyntheticHand], imageSize: Vec2 = Vec2(720, 1280)) -> VisionFrame {
    VisionFrame(timestamp: time, imageSize: imageSize, hands: hands.map { $0.observation() })
}

/// 左手と右手を横に並べた、標準のテスト用の両手
func standardHands() -> (left: SyntheticHand, right: SyntheticHand) {
    (SyntheticHand(chirality: .left, origin: Vec2(200, 1000)),
     SyntheticHand(chirality: .right, origin: Vec2(520, 1000)))
}
