import Foundation
@testable import ARKeyboardCore

/// テスト用の「人工的な手」。
/// 手の座標(x: 親指側+, y: 前+、単位は手首〜中指付け根の長さ)で関節の位置を決めておき、
/// 好きな位置・回転・大きさで画像上に置いた HandObservation を作ります。
struct SyntheticHand {
    var chirality: Chirality
    /// 画像上の手首の位置(ピクセル)
    var origin = Vec2(360, 900)
    /// 画像上での回転(ラジアン)。0 なら指先が画像の上を向く。
    var rotation: Double = 0
    /// 手首〜中指付け根の長さ(ピクセル)
    var scale: Double = 150
    /// 奥行き方向(前後)の縮み(1 = 真上から、0.6 = 斜めから見て前後が 60% に縮んで見える)
    var forwardSquash: Double = 1
    /// 各関節の手の座標(必要に応じてテストで書き換える)
    var local: [Joint: Vec2] = SyntheticHand.homeLocal
    var confidence: Double = 0.9

    /// ホームポジションの手の形(だいたい実物の比率)
    static let homeLocal: [Joint: Vec2] = {
        var j: [Joint: Vec2] = [
            .wrist: Vec2(0, 0),
            .thumbCMC: Vec2(0.25, 0.2), .thumbMP: Vec2(0.5, 0.4), .thumbIP: Vec2(0.65, 0.5), .thumbTip: Vec2(0.75, 0.6),
            .indexMCP: Vec2(0.30, 0.97), .middleMCP: Vec2(0, 1), .ringMCP: Vec2(-0.23, 0.95), .littleMCP: Vec2(-0.45, 0.88),
            .indexTip: Vec2(0.35, 1.55), .middleTip: Vec2(0.08, 1.62), .ringTip: Vec2(-0.18, 1.58), .littleTip: Vec2(-0.42, 1.45),
        ]
        // PIP / DIP は付け根と指先の間に置く
        let fingers: [(Joint, Joint, Joint, Joint)] = [
            (.indexMCP, .indexPIP, .indexDIP, .indexTip),
            (.middleMCP, .middlePIP, .middleDIP, .middleTip),
            (.ringMCP, .ringPIP, .ringDIP, .ringTip),
            (.littleMCP, .littlePIP, .littleDIP, .littleTip),
        ]
        for (mcp, pip, dip, tip) in fingers {
            j[pip] = Vec2.lerp(j[mcp]!, j[tip]!, 0.4)
            j[dip] = Vec2.lerp(j[mcp]!, j[tip]!, 0.75)
        }
        return j
    }()

    /// 画像上での「前」と「親指側」の向き。
    /// 手のひらを下にして上から撮ると、左手の親指は右(+x)、右手の親指は左(−x)に見える。
    var forwardAxis: Vec2 { Vec2(sin(rotation), -cos(rotation)) }
    var thumbAxis: Vec2 {
        let right = Vec2(cos(rotation), sin(rotation))
        return chirality == .left ? right : -right
    }

    func imagePoint(_ localPoint: Vec2) -> Vec2 {
        origin + thumbAxis * (localPoint.x * scale) + forwardAxis * (localPoint.y * scale * forwardSquash)
    }

    func observation(reportedChirality: Chirality?? = nil) -> HandObservation {
        var joints: [Joint: JointPoint] = [:]
        for (joint, p) in local {
            joints[joint] = JointPoint(position: imagePoint(p), confidence: confidence)
        }
        let reported: Chirality? = reportedChirality ?? chirality
        return HandObservation(chirality: reported, joints: joints)
    }

    /// 指先を手の座標で動かした手を返す
    func moving(_ finger: Finger, by delta: Vec2) -> SyntheticHand {
        var copy = self
        copy.local[Joint.tip(of: finger)]! += delta
        copy.local[Joint.dip(of: finger)]! += delta * 0.7
        return copy
    }
}

/// 左右そろった VisionFrame を作る
func makeFrame(time: Double, hands: [SyntheticHand], imageSize: Vec2 = Vec2(720, 1280)) -> VisionFrame {
    VisionFrame(timestamp: time, imageSize: imageSize, hands: hands.map { $0.observation() })
}

/// 左手と右手を横に並べた、標準のテスト用の両手
func standardHands() -> (left: SyntheticHand, right: SyntheticHand) {
    (SyntheticHand(chirality: .left, origin: Vec2(200, 1000)),
     SyntheticHand(chirality: .right, origin: Vec2(520, 1000)))
}
