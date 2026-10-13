import SwiftUI

/// タッチヒートマップ(7-2): 実際に押した場所を、キーごとの色の点で重ねて表示する。
///
/// 個人適応で学習に使ったタップの位置(キーの中心からのずれ)を、今のキー配置の上に描きます。
/// 点の集まりがキーの中心からずれていれば、その方向に押しがちだということです
/// (SwiftKey の Tap Map / heatmap に相当)。
struct HeatmapOverlayView: View {
    let points: [Chirality: [(key: Key, points: [Vec2])]]
    let frames: [Chirality: HandFrame]
    let projection: LayoutProjection

    var body: some View {
        Canvas { context, _ in
            for (chirality, entries) in points {
                guard let frame = frames[chirality] else { continue }
                for (i, entry) in entries.enumerated() {
                    let color = Color(hue: Double(i) / Double(max(entries.count, 1)), saturation: 0.85, brightness: 1)
                    for p in entry.points {
                        let v = projection.viewPoint(fromLayout: frame.toImage(p))
                        let rect = CGRect(x: v.x - 3, y: v.y - 3, width: 6, height: 6)
                        context.fill(Path(ellipseIn: rect), with: .color(color.opacity(0.45)))
                    }
                    // 平均の位置(押しがちな中心)を大きめの白丸で
                    if let mean = Vec2.average(entry.points) {
                        let v = projection.viewPoint(fromLayout: frame.toImage(mean))
                        let rect = CGRect(x: v.x - 5, y: v.y - 5, width: 10, height: 10)
                        context.stroke(Path(ellipseIn: rect), with: .color(.white), lineWidth: 2)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}
