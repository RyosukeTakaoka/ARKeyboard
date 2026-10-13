import SwiftUI

/// キャリブレーション中に、やることと進み具合を表示する View。
struct CalibrationOverlayView: View {
    let phase: Calibrator.Phase
    let message: String
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("キャリブレーション")
                .font(.headline)

            // 指を置く場所の図(左: A S D F / 右: J K L ;)
            HStack(spacing: 24) {
                homeRow(["A", "S", "D", "F"], color: .cyan)
                homeRow(["J", "K", "L", ";"], color: .orange)
            }

            Text(message)
                .font(.callout)
                .multilineTextAlignment(.center)

            // 静止できている時間を、円のゲージで表示
            ZStack {
                Circle().stroke(.white.opacity(0.25), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(.green, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))  // 12時の位置から始める
                Text("\(Int(progress * 100))%")
                    .font(.caption.monospacedDigit())
            }
            .frame(width: 64, height: 64)
            .animation(.linear(duration: 0.1), value: progress)

            Button("やめる", role: .cancel, action: onCancel)
                .buttonStyle(.bordered)
        }
        .padding(20)
        .foregroundStyle(.white)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
        .padding()
    }

    private var progress: Double {
        if case .holding(let progress) = phase { return progress }
        if phase == .finished { return 1 }
        return 0
    }

    private func homeRow(_ labels: [String], color: Color) -> some View {
        HStack(spacing: 4) {
            ForEach(labels, id: \.self) { label in
                Text(label)
                    .font(.system(.body, design: .monospaced).bold())
                    .frame(width: 28, height: 28)
                    .background(color.opacity(0.35), in: RoundedRectangle(cornerRadius: 5))
            }
        }
    }
}
