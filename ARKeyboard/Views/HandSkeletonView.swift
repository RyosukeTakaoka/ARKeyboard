import SwiftUI

/// 検出した手の関節点と骨格を、カメラ映像の上に描く View。
/// 「Vision がちゃんと手を見つけているか」を目で確認するためのものです。
/// あわせて、手の座標系(前=緑、親指側=赤の矢印)も描きます。
struct HandSkeletonView: View {
    let hands: [Chirality: HandObservation]
    /// キー配置の基準にしている手の座標系(キャリブレーション後のみ)
    let frames: [Chirality: HandFrame]
    /// 画像のピクセル座標 → 画面座標 の変換
    let converter: CoordinateConverter
    /// この信頼度より低い点は描かない(=計算にも使わない点)
    var minConfidence: Double = 0.3
    /// 机の座標 → 画像(机モードのときだけ。座標軸の表示に使う)
    var planeToImage: Homography? = nil

    var body: some View {
        // Canvas は、たくさんの線や点を高速に描くのに向いた View です。
        Canvas { context, _ in
            for (chirality, hand) in hands {
                let color = Self.color(for: chirality)

                // 骨格(手首 → 各指の付け根 → 指先)を線で結ぶ
                for finger in Finger.allCases {
                    var path = Path()
                    var started = false
                    for joint in Joint.chain(of: finger) {
                        guard let p = hand.position(joint, minConfidence: minConfidence) else {
                            started = false
                            continue
                        }
                        let v = converter.viewPoint(fromImage: p).cgPoint
                        if started { path.addLine(to: v) } else { path.move(to: v); started = true }
                    }
                    context.stroke(path, with: .color(color.opacity(0.6)), lineWidth: 2)
                }

                // 関節点(信頼度が高いほど不透明に)
                for (joint, point) in hand.joints where point.confidence >= minConfidence {
                    let v = converter.viewPoint(fromImage: point.position)
                    let isTip = Finger.allCases.contains { Joint.tip(of: $0) == joint }
                    let r: Double = isTip ? 5 : 3
                    let rect = CGRect(x: v.x - r, y: v.y - r, width: r * 2, height: r * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(color.opacity(0.4 + 0.6 * point.confidence)))
                }
            }

            // 手の座標系の軸(前 = 緑、親指側 = 赤)。長さは手の大きさの 0.5 倍。
            let projection = LayoutProjection(converter: converter, planeToImage: planeToImage)
            for (_, frame) in frames {
                let origin = projection.viewPoint(fromLayout: frame.origin).cgPoint
                let forwardEnd = projection.viewPoint(fromLayout: frame.toImage(Vec2(0, 0.5))).cgPoint
                let thumbEnd = projection.viewPoint(fromLayout: frame.toImage(Vec2(0.5, 0))).cgPoint
                var forwardPath = Path()
                forwardPath.move(to: origin)
                forwardPath.addLine(to: forwardEnd)
                context.stroke(forwardPath, with: .color(.green), lineWidth: 3)
                var thumbPath = Path()
                thumbPath.move(to: origin)
                thumbPath.addLine(to: thumbEnd)
                context.stroke(thumbPath, with: .color(.red), lineWidth: 3)
            }
        }
        // 下にあるボタンなどのタッチを邪魔しないように、この View はタッチを受け取らない
        .allowsHitTesting(false)
    }

    /// 左手は水色、右手はオレンジ
    static func color(for chirality: Chirality) -> Color {
        switch chirality {
        case .left: return .cyan
        case .right: return .orange
        }
    }
}
