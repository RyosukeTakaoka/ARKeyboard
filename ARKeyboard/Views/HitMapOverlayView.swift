import SwiftUI

/// 当たり判定ビュー(7-3)。
///
/// 手のまわりを細かい格子に分け、各点を「そこを押したら、どのキーが選ばれるか」
/// (事後確率が最大のキー)の色で塗ります。色が濃いほど、そのキーである確率が高い場所です。
///
/// 直前の文字(文脈)が変わると、言語モデルの事前確率が変わるので、
/// 「次に来やすいキー」の領域が広がり、来にくいキーの領域が縮みます(Apple 型の動的な当たり判定)。
/// キーの中央(アンカー)は、どんな文脈でもそのキーのままです。
struct HitMapOverlayView: View {
    let hitMaps: [Chirality: HitMap]
    let keys: [Chirality: [Key]]
    let frames: [Chirality: HandFrame]
    /// キー配置の座標 → 画面の座標(机モードではホモグラフィーの逆変換も含む)
    let projection: LayoutProjection

    var body: some View {
        Canvas { context, _ in
            for (chirality, map) in hitMaps {
                guard let frame = frames[chirality], let handKeys = keys[chirality] else { continue }
                // キーごとに色を決める(キーの並び順で色相を変える)
                let letterKeys = handKeys.filter { !$0.isSpace }
                var colors: [String: Color] = [:]
                for (i, key) in letterKeys.enumerated() {
                    colors[key.id] = Color(hue: Double(i) / Double(max(letterKeys.count, 1)), saturation: 0.8, brightness: 0.95)
                }
                let half = map.cellSize / 2
                for cell in map.cells {
                    // 格子の4つの角(キー配置の座標)→ 画像 → 画面
                    let corners = [
                        Vec2(-half.x, -half.y), Vec2(half.x, -half.y), Vec2(half.x, half.y), Vec2(-half.x, half.y),
                    ].map { projection.viewPoint(fromLayout: frame.toImage(cell.center + $0)).cgPoint }
                    var path = Path()
                    path.addLines(corners)
                    path.closeSubpath()
                    let color = colors[cell.keyID] ?? .gray
                    context.fill(path, with: .color(color.opacity(0.12 + 0.4 * cell.probability)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}
