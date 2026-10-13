import SwiftUI

/// 手書きモードの表示: 書きかけの画、ペンの状態、機能パッドの指の割り当て
struct HandwritingOverlayView: View {
    let strokes: [[Vec2]]
    let penDown: Bool
    let hands: [Chirality: HandObservation]
    let config: HandwritingConfig
    let functionConfig: FlickConfig
    let converter: CoordinateConverter

    var body: some View {
        Canvas { context, _ in
            // 画(画像の座標 → 画面の座標)
            for stroke in strokes {
                guard let first = stroke.first else { continue }
                var path = Path()
                path.move(to: converter.viewPoint(fromImage: first).cgPoint)
                for p in stroke.dropFirst() { path.addLine(to: converter.viewPoint(fromImage: p).cgPoint) }
                context.stroke(path, with: .color(.yellow), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            }
            // ペン(親指と人差し指の間)
            if let hand = hands[config.hand],
               let thumb = hand.position(.thumbTip, minConfidence: 0.3),
               let index = hand.position(.indexTip, minConfidence: 0.3) {
                let p = converter.viewPoint(fromImage: (thumb + index) / 2).cgPoint
                let r: CGFloat = penDown ? 9 : 6
                let circle = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
                if penDown {
                    context.fill(circle, with: .color(.yellow))
                } else {
                    context.stroke(circle, with: .color(.white), lineWidth: 2)
                }
            }
            // 機能パッド(もう一方の手)の指の割り当て
            for (chirality, hand) in hands where chirality != config.hand {
                for finger in Finger.allCases {
                    let action = functionConfig.action(for: finger)
                    guard action != .none, action != .modifier,
                          let tip = hand.position(Joint.tip(of: finger), minConfidence: 0.3) else { continue }
                    let p = converter.viewPoint(fromImage: tip).cgPoint
                    let name = action == .nextCandidate ? "次の候補" : action.japaneseName
                    let rect = CGRect(x: p.x - 26, y: p.y - 30, width: 52, height: 18)
                    context.fill(Path(roundedRect: rect, cornerRadius: 5), with: .color(.cyan.opacity(0.85)))
                    context.draw(Text(name).font(.system(size: 11, weight: .bold)).foregroundColor(.black),
                                 at: CGPoint(x: rect.midX, y: rect.midY))
                }
            }
        }
        .allowsHitTesting(false)
    }
}
