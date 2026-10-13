import SwiftUI

/// フリックパッドの表示(フリックモード)。
/// - 12 個のキー: 中央に行の文字(あ・か…)、上下左右にその方向で入力される文字
/// - 指先の下のキーを強調し、そのキーのまわりに「扇形」を描く。
///   扇の広さは、文脈(直前の仮名)から見た各方向の出やすさ(言語モデルの事前確率)。
///   次に来やすい段ほど扇が広くなり、実効的な判定角度が広がる様子を見せる(7-4)
/// - フリックしている最中は、始点から今の位置への矢印
/// - 機能パッドの手は、指先のそばに割り当て(削除・改行など)を表示
struct FlickPadOverlayView: View {
    let keys: [FlickKey]
    let frames: [Chirality: HandFrame]
    let hoveredKeyIDs: Set<String>
    var pressedKeys: [String: Date] = [:]
    let activeFlicks: [FingerID: (start: Vec2, displacement: Vec2)]
    /// 指先の下のキーの、方向ごとの事前確率(扇形の広さ)
    let hoveredPriors: [String: [FlickDirection: Double]]
    let hands: [Chirality: HandObservation]
    let config: FlickConfig
    let projection: LayoutProjection

    var body: some View {
        Canvas { context, _ in
            let now = Date()
            for key in keys {
                guard let frame = frames[key.hand] else { continue }
                let keyboardRight: Double = key.hand == .left ? 1 : -1
                func view(_ local: Vec2) -> CGPoint { projection.viewPoint(fromLayout: frame.toImage(local)).cgPoint }

                // キーの四角
                let half = key.size / 2
                var path = Path()
                path.addLines([Vec2(-half.x, -half.y), Vec2(half.x, -half.y), Vec2(half.x, half.y), Vec2(-half.x, half.y)]
                    .map { view(key.center + $0) })
                path.closeSubpath()
                let isHovered = hoveredKeyIDs.contains(key.id)
                let isFlashing = (pressedKeys[key.id].map { now.timeIntervalSince($0) } ?? .infinity) < 0.25
                context.fill(path, with: .color(isFlashing ? .white.opacity(0.8) : (isHovered ? .orange.opacity(0.45) : .black.opacity(0.25))))
                context.stroke(path, with: .color(.orange.opacity(isHovered ? 1 : 0.5)), lineWidth: isHovered ? 2 : 1)

                // 扇形(指先の下のキーだけ)
                if isHovered, let priors = hoveredPriors[key.id] {
                    let flickPriors = FlickDirection.allCases.filter { $0 != .tap }
                    let total = flickPriors.reduce(0.0) { $0 + (priors[$1] ?? 0) }
                    let radius = max(key.size.x, key.size.y) * 0.9
                    for direction in flickPriors {
                        guard let mu = direction.angle, let p = priors[direction], total > 0 else { continue }
                        // 広さ = 4方向の中での出やすさの割合 × 360 度
                        let width = 2 * Double.pi * p / total
                        var fan = Path()
                        fan.move(to: view(key.center))
                        for step in 0...12 {
                            let a = mu - width / 2 + width * Double(step) / 12
                            fan.addLine(to: view(key.center + Vec2(cos(a) * radius * keyboardRight, sin(a) * radius)))
                        }
                        fan.closeSubpath()
                        context.fill(fan, with: .color(.yellow.opacity(0.12 + 0.3 * p / total)))
                    }
                }

                // 文字: 中央に行の文字、上下左右に各方向の文字
                context.draw(Text(key.definition.label).font(.system(size: 17, weight: .bold)).foregroundColor(.white),
                             at: view(key.center))
                let offsets: [(FlickDirection, Vec2)] = [
                    (.left, Vec2(-0.36 * key.size.x * keyboardRight, 0)), (.up, Vec2(0, 0.34 * key.size.y)),
                    (.right, Vec2(0.36 * key.size.x * keyboardRight, 0)), (.down, Vec2(0, -0.34 * key.size.y)),
                ]
                for (direction, offset) in offsets {
                    guard let output = key.definition.output(for: direction) else { continue }
                    context.draw(Text(output).font(.system(size: 10)).foregroundColor(.white.opacity(0.85)),
                                 at: view(key.center + offset))
                }
            }

            // フリック中の矢印
            for (finger, flick) in activeFlicks {
                guard let frame = frames[finger.chirality] else { continue }
                let from = projection.viewPoint(fromLayout: frame.toImage(flick.start)).cgPoint
                let to = projection.viewPoint(fromLayout: frame.toImage(flick.start + flick.displacement)).cgPoint
                var arrow = Path()
                arrow.move(to: from)
                arrow.addLine(to: to)
                context.stroke(arrow, with: .color(.green), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            }

            // 機能パッドの指の割り当て
            for (chirality, hand) in hands where !config.isFlickHand(chirality) {
                for finger in Finger.allCases {
                    let action = config.action(for: finger)
                    guard action != .none, let tip = hand.position(Joint.tip(of: finger), minConfidence: 0.3) else { continue }
                    let p = projection.converter.viewPoint(fromImage: tip)
                    let label = Text(action.japaneseName).font(.system(size: 11, weight: .bold)).foregroundColor(.black)
                    let rect = CGRect(x: p.x - 24, y: p.y - 30, width: 48, height: 18)
                    context.fill(Path(roundedRect: rect, cornerRadius: 5), with: .color(.cyan.opacity(0.85)))
                    context.draw(label, at: CGPoint(x: rect.midX, y: rect.midY))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// 今の仮名の並びの候補(上位3つ)。タップで選べる
struct FlickCandidateBar: View {
    let candidates: [String]
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("候補").font(.caption2).foregroundStyle(.secondary)
            ForEach(Array(candidates.enumerated()), id: \.offset) { index, candidate in
                Button(candidate) { onSelect(index) }
                    .buttonStyle(.bordered)
                    .font(.callout)
            }
            Spacer()
        }
        .padding(.horizontal)
    }
}
