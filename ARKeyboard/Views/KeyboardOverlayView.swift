import SwiftUI

/// キー配置を半透明で描き、指先の下にあるキーを光らせる View。
///
/// キーは「手の座標」で定義されているので、描くときは次の順に変換します。
///   手の座標(Key.center)→ HandFrame.toImage → 画像のピクセル座標 → CoordinateConverter → 画面の座標
/// 手の座標系は回転しているので、キーは長方形ではなく「回転した四角形」として4つの角を変換して描きます。
struct KeyboardOverlayView: View {
    let keys: [Chirality: [Key]]
    let frames: [Chirality: HandFrame]
    let hoveredKeyIDs: Set<String>
    /// 最近押されたキーと、押された時刻(押した瞬間に強く光らせる)
    var pressedKeys: [String: Date] = [:]
    let converter: CoordinateConverter

    /// 押した後に光り続ける時間(秒)
    private let flashDuration = 0.25

    var body: some View {
        Canvas { context, _ in
            let now = Date()
            for (chirality, handKeys) in keys {
                guard let frame = frames[chirality] else { continue }
                let baseColor = HandSkeletonView.color(for: chirality)

                for key in handKeys {
                    // キーの4つの角(手の座標)→ 画面の座標
                    let half = key.size / 2
                    let corners = [
                        Vec2(-half.x, -half.y), Vec2(half.x, -half.y),
                        Vec2(half.x, half.y), Vec2(-half.x, half.y),
                    ].map { converter.viewPoint(fromImage: frame.toImage(key.center + $0)).cgPoint }

                    var path = Path()
                    path.addLines(corners)
                    path.closeSubpath()

                    // 押した直後(flashDuration 秒)は白く強く光らせ、指先が乗っているキーは色を濃くする
                    let pressedAge = pressedKeys[key.id].map { now.timeIntervalSince($0) }
                    let isFlashing = (pressedAge ?? .infinity) < flashDuration
                    let isHovered = hoveredKeyIDs.contains(key.id)

                    let fill: Color
                    if isFlashing {
                        fill = .white.opacity(0.85)
                    } else if isHovered {
                        fill = baseColor.opacity(0.55)
                    } else {
                        fill = .black.opacity(0.18)
                    }
                    context.fill(path, with: .color(fill))
                    context.stroke(path, with: .color(baseColor.opacity(isHovered ? 1 : 0.5)),
                                   lineWidth: isHovered ? 2 : 1)

                    // 文字
                    let center = converter.viewPoint(fromImage: frame.toImage(key.center)).cgPoint
                    let text = Text(key.label)
                        .font(.system(size: key.isSpace ? 11 : 15, weight: .bold, design: .monospaced))
                        .foregroundColor(isFlashing ? .black : .white)
                    context.draw(text, at: center)
                }
            }
        }
        .allowsHitTesting(false)
    }
}
