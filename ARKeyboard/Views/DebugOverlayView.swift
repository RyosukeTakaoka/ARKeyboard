import SwiftUI

/// タップ判定を調整するためのデバッグ表示。
/// - 選んだ1本の指の「下向きの速さ」の折れ線グラフ(しきい値の線つき)
/// - FPS(1秒に何コマ処理できているか)
/// - 検出した手の数
/// - 音のオンセットの波形(マイクを使うとき)
/// - 直近のタップのログ
struct DebugOverlayView: View {
    @Bindable var viewModel: KeyboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                stat("FPS", String(format: "%.0f", viewModel.fps),
                     color: viewModel.fps >= 25 ? .green : .orange)
                stat("手", "\(viewModel.detectedHandCount)",
                     color: viewModel.detectedHandCount == 2 ? .green : .orange)
                stat("左右", handsText, color: .white)
                Spacer()
                // グラフに出す指を選ぶメニュー
                Picker("グラフの指", selection: $viewModel.settings.debugFinger) {
                    ForEach(FingerID.all) { finger in
                        Text(finger.japaneseName).tag(finger)
                    }
                }
                .pickerStyle(.menu)
                .tint(.white)
                .font(.caption)
            }

            SignalGraphView(samples: viewModel.signalHistory,
                            duration: KeyboardViewModel.signalHistoryDuration)
                .frame(height: 90)

            HStack(spacing: 10) {
                legend(color: .white, text: "下向きの速さ")
                legend(color: .red, text: "しきい値")
                legend(color: .yellow, text: "下ろし中")
                legend(color: .green, text: "タップ")
            }
            .font(.system(size: 9))

            if viewModel.settings.features.audioOnset {
                HStack {
                    Text("マイク: \(viewModel.audioStatus)")
                    if viewModel.settings.features.motionAssist {
                        Text("振動: \(viewModel.motionStatus)")
                    }
                }
                .font(.system(size: 10))
                AudioGraphView(features: viewModel.audioHistory,
                               onsets: viewModel.recentOnsets.filter { $0.source == .audio },
                               visionTapTimes: viewModel.recentVisionTapTimes,
                               duration: KeyboardViewModel.signalHistoryDuration)
                    .frame(height: 50)
                HStack(spacing: 10) {
                    legend(color: .cyan, text: "音の変化(flux)")
                    legend(color: .red, text: "音の立ち上がり")
                    legend(color: .green, text: "カメラのタップ")
                }
                .font(.system(size: 9))
            }

            // タップのログ(新しい順)
            VStack(alignment: .leading, spacing: 2) {
                if viewModel.tapLog.isEmpty {
                    Text("タップのログはまだありません")
                        .foregroundStyle(.white.opacity(0.6))
                }
                ForEach(viewModel.tapLog.prefix(6)) { entry in
                    Text(entry.summary)
                        .foregroundStyle(entry.keyLabel == nil ? .orange : .white)
                        .lineLimit(1)
                }
            }
            .font(.system(size: 10, design: .monospaced))
        }
        .foregroundStyle(.white)
        .font(.caption)
        .padding(10)
        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    private var handsText: String {
        let names = Chirality.allCases.filter { viewModel.hands[$0] != nil }.map(\.japaneseName)
        return names.isEmpty ? "なし" : names.joined(separator: "・")
    }

    private func stat(_ title: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.system(size: 9)).foregroundStyle(.white.opacity(0.7))
            Text(value).font(.system(.callout, design: .monospaced).bold()).foregroundStyle(color)
        }
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 10, height: 3)
            Text(text)
        }
    }
}

/// 速度の折れ線グラフ。横軸は時間(右端が現在)、縦軸は下向きの速さ(手/秒)。
struct SignalGraphView: View {
    let samples: [FingerSignalSample]
    /// 横軸に表示する時間(秒)
    let duration: Double

    var body: some View {
        Canvas { context, size in
            guard let latest = samples.last else {
                context.draw(Text("指が見えていません").font(.caption2).foregroundColor(.white.opacity(0.6)),
                             at: CGPoint(x: size.width / 2, y: size.height / 2))
                return
            }
            // 縦軸の範囲: しきい値の2倍と、実際の最大値の大きい方(上下対称)
            let maxAbs = max(latest.threshold * 2, samples.map { abs($0.speed) }.max() ?? 0, 0.1)
            func x(_ t: Double) -> Double { size.width * (1 - (latest.timestamp - t) / duration) }
            func y(_ v: Double) -> Double { size.height / 2 - (v / maxAbs) * (size.height / 2) }

            // 0 の線
            var zero = Path()
            zero.move(to: CGPoint(x: 0, y: y(0)))
            zero.addLine(to: CGPoint(x: size.width, y: y(0)))
            context.stroke(zero, with: .color(.white.opacity(0.3)), lineWidth: 1)

            // しきい値の線(点線)
            var thresholdPath = Path()
            thresholdPath.move(to: CGPoint(x: 0, y: y(latest.threshold)))
            thresholdPath.addLine(to: CGPoint(x: size.width, y: y(latest.threshold)))
            context.stroke(thresholdPath, with: .color(.red), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))

            // 下ろし中の点と、タップの縦線
            for sample in samples {
                let px = x(sample.timestamp)
                if sample.didTap {
                    var line = Path()
                    line.move(to: CGPoint(x: px, y: 0))
                    line.addLine(to: CGPoint(x: px, y: size.height))
                    context.stroke(line, with: .color(.green), lineWidth: 2)
                } else if sample.isDescending {
                    let rect = CGRect(x: px - 2, y: y(sample.speed) - 2, width: 4, height: 4)
                    context.fill(Path(ellipseIn: rect), with: .color(.yellow))
                }
            }

            // 速さの折れ線
            var line = Path()
            for (i, sample) in samples.enumerated() {
                let point = CGPoint(x: x(sample.timestamp), y: y(sample.speed))
                if i == 0 { line.move(to: point) } else { line.addLine(to: point) }
            }
            context.stroke(line, with: .color(.white), lineWidth: 1.5)

            // 縦軸の目盛り
            context.draw(Text(String(format: "+%.1f", maxAbs)).font(.system(size: 8)).foregroundColor(.white.opacity(0.7)),
                         at: CGPoint(x: 2, y: 2), anchor: .topLeading)
            context.draw(Text(String(format: "-%.1f", maxAbs)).font(.system(size: 8)).foregroundColor(.white.opacity(0.7)),
                         at: CGPoint(x: 2, y: size.height - 2), anchor: .bottomLeading)
        }
        .background(.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// 音のオンセットの波形。横軸は時間(右端が最新)、縦軸はスペクトルの増え方(flux)。
/// 赤い縦線(音の立ち上がり)と緑の縦線(カメラのタップ候補)が近くに並んでいれば、
/// 二重条件の時間窓に入っている、ということです。
struct AudioGraphView: View {
    let features: [AudioFeature]
    let onsets: [OnsetEvent]
    let visionTapTimes: [Double]
    let duration: Double

    var body: some View {
        Canvas { context, size in
            guard let latest = features.last else {
                context.draw(Text("音のデータがありません").font(.caption2).foregroundColor(.white.opacity(0.6)),
                             at: CGPoint(x: size.width / 2, y: size.height / 2))
                return
            }
            let maxValue = max(features.map { max($0.flux, $0.threshold) }.max() ?? 0, 1e-6)
            func x(_ t: Double) -> Double { size.width * (1 - (latest.time - t) / duration) }
            func y(_ v: Double) -> Double { size.height - (v / maxValue) * size.height }

            // しきい値(点線)
            var thresholdPath = Path()
            for (i, f) in features.enumerated() {
                let p = CGPoint(x: x(f.time), y: y(f.threshold))
                if i == 0 { thresholdPath.move(to: p) } else { thresholdPath.addLine(to: p) }
            }
            context.stroke(thresholdPath, with: .color(.red.opacity(0.6)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

            // flux の折れ線
            var line = Path()
            for (i, f) in features.enumerated() {
                let p = CGPoint(x: x(f.time), y: y(f.flux))
                if i == 0 { line.move(to: p) } else { line.addLine(to: p) }
            }
            context.stroke(line, with: .color(.cyan), lineWidth: 1.2)

            // 縦線: 音の立ち上がり(赤)とカメラのタップ(緑)
            func vertical(_ t: Double, _ color: Color, top: Bool) {
                let px = x(t)
                guard px >= 0 else { return }
                var path = Path()
                path.move(to: CGPoint(x: px, y: top ? 0 : size.height / 2))
                path.addLine(to: CGPoint(x: px, y: top ? size.height / 2 : size.height))
                context.stroke(path, with: .color(color), lineWidth: 2)
            }
            for onset in onsets { vertical(onset.time, .red, top: true) }
            for t in visionTapTimes { vertical(t, .green, top: false) }
        }
        .background(.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
