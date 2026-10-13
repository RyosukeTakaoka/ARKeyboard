import SwiftUI

/// 机の四隅を登録する画面(机モード)。
/// カメラ映像の上で、机の「奥の左 → 奥の右 → 手前の右 → 手前の左」の順にタップします。
/// 4つそろうと、ホモグラフィー(真上から見た座標への変換)が計算されます。
struct DeskRegistrationView: View {
    @Bindable var viewModel: KeyboardViewModel
    let converter: CoordinateConverter

    var body: some View {
        ZStack {
            // 画面全体でタップを受け取る透明な板
            Color.black.opacity(0.15)
                .contentShape(Rectangle())
                .onTapGesture(coordinateSpace: .local) { location in
                    viewModel.addDeskCorner(viewPoint: Vec2(location), viewSize: converter.viewSize)
                }

            // ここまでにタップした点
            Canvas { context, _ in
                let points = viewModel.deskCornerDraft.map { converter.viewPoint(fromImage: $0).cgPoint }
                for (i, p) in points.enumerated() {
                    context.fill(Path(ellipseIn: CGRect(x: p.x - 8, y: p.y - 8, width: 16, height: 16)), with: .color(.yellow))
                    context.draw(Text("\(i + 1)").font(.caption.bold()).foregroundColor(.black), at: p)
                }
                if points.count >= 2 {
                    var path = Path()
                    path.addLines(points)
                    context.stroke(path, with: .color(.yellow), lineWidth: 2)
                }
            }
            .allowsHitTesting(false)

            VStack {
                Spacer()
                VStack(spacing: 8) {
                    let index = min(viewModel.deskCornerDraft.count, 3)
                    Text("机の四隅を登録(\(viewModel.deskCornerDraft.count + 1)/4)")
                        .font(.headline)
                    Text("「\(KeyboardViewModel.deskCornerNames[index])」の角をタップしてください")
                    Text("登録する範囲: 幅 \(Int(viewModel.settings.deskWidthCm)) cm × 奥行き \(Int(viewModel.settings.deskDepthCm)) cm(設定で変更)")
                        .font(.caption)
                    Button("やめる", role: .cancel) { viewModel.cancelDeskRegistration() }
                        .buttonStyle(.bordered)
                }
                .padding()
                .foregroundStyle(.white)
                .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
                .padding(.bottom, 160)
            }
        }
    }
}

/// 登録した机の範囲を、うすい枠で表示する
struct DeskPlaneOutlineView: View {
    let plane: DeskPlane
    let converter: CoordinateConverter

    var body: some View {
        Canvas { context, _ in
            var path = Path()
            path.addLines(plane.imageCorners.map { converter.viewPoint(fromImage: $0).cgPoint })
            path.closeSubpath()
            context.stroke(path, with: .color(.yellow.opacity(0.6)), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        }
        .allowsHitTesting(false)
    }
}
