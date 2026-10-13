import SwiftUI

/// 練習モードの表示: お題、色分けした進み具合、正解率と速さ。
struct PracticeView: View {
    let session: PracticeSession
    /// 「今の時刻」を返す(経過時間の計算用)
    let now: () -> Double
    let onNext: () -> Void
    let onStop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("練習モード", systemImage: "graduationcap")
                    .font(.caption.bold())
                Spacer()
                Button("次の文", action: onNext)
                    .font(.caption)
                Button("終了", role: .cancel, action: onStop)
                    .font(.caption)
            }

            // お題を1文字ずつ色分けして表示
            coloredTarget
                .font(.system(.title3, design: .monospaced))

            // 速さは時間とともに変わるので、0.5秒ごとに描き直す
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                let cpm = session.charactersPerMinute(now: now())
                HStack(spacing: 16) {
                    Text("正解率 \(Int((session.accuracy * 100).rounded()))%")
                    Text("速さ \(Int(cpm)) 文字/分(\(String(format: "%.1f", cpm / 5)) WPM)")
                    if session.isFinished {
                        Text("完了!").bold().foregroundStyle(.green)
                    }
                }
                .font(.caption.monospacedDigit())
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
    }

    /// Text は「+」でつなげると、文字ごとに色の違う1つの Text にできます。
    private var coloredTarget: Text {
        session.characterStates.reduce(Text("")) { result, item in
            // スペースは見えないので、打ち間違えたときだけ「␣」で見えるようにする
            let shown = item.character == " " && item.state == .wrong ? "␣" : String(item.character)
            var piece = Text(shown)
            switch item.state {
            case .correct: piece = piece.foregroundColor(.green)
            case .wrong: piece = piece.foregroundColor(.red)
            case .current: piece = piece.underline().bold()
            case .pending: piece = piece.foregroundColor(.secondary)
            }
            return result + piece
        }
    }
}
