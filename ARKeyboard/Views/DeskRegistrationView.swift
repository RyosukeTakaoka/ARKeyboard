import SwiftUI

/// 机の四隅(または 3×3 の 9 点)を登録する画面(机モード)。
/// - 指先で登録(既定): 人差し指の先で机の点を 0.8 秒押さえると記録されます(位置を平均するので正確)
/// - 画面タップ: カメラ映像の上で、その点をタップします
/// 点がそろうと、ホモグラフィー(真上から見た座標への変換)が計算されます。
struct DeskRegistrationView: View {
    @Bindable var viewModel: KeyboardViewModel
    let converter: CoordinateConverter

    var body: some View {
        ZStack {
            // 画面タップで登録するときだけ、画面全体でタップを受け取る
            if !viewModel.settings.deskRegisterWithFingertip {
                Color.black.opacity(0.15)
                    .contentShape(Rectangle())
                    .onTapGesture(coordinateSpace: .local) { location in
                        viewModel.addDeskCorner(viewPoint: Vec2(location), viewSize: converter.viewSize)
                    }
            }

            // ここまでに登録した点
            Canvas { context, _ in
                let points = viewModel.deskCornerDraft.map { converter.viewPoint(fromImage: $0).cgPoint }
                for (i, p) in points.enumerated() {
                    context.fill(Path(ellipseIn: CGRect(x: p.x - 8, y: p.y - 8, width: 16, height: 16)), with: .color(.yellow))
                    context.draw(Text("\(i + 1)").font(.caption.bold()).foregroundColor(.black), at: p)
                }
            }
            .allowsHitTesting(false)

            VStack {
                Spacer()
                VStack(spacing: 8) {
                    let names = viewModel.deskPointNames
                    let index = min(viewModel.deskCornerDraft.count, names.count - 1)
                    Text("机の登録(\(viewModel.deskCornerDraft.count + 1)/\(names.count))")
                        .font(.headline)
                    if viewModel.settings.deskRegisterWithFingertip {
                        Text("人差し指の先で「\(names[index])」を押さえて、止めてください")
                        ProgressView(value: viewModel.deskCaptureProgress)
                            .frame(width: 180)
                    } else {
                        Text("「\(names[index])」の位置をタップしてください")
                    }
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
