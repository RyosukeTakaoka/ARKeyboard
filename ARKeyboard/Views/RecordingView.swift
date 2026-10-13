import SwiftUI

/// 記録モードの表示: 次に打ってほしい文字を大きく出す。
/// 文字が入力されると(正解でも不正解でも)次へ進み、最後まで行くと自動で保存されます。
struct RecordingView: View {
    @Bindable var viewModel: KeyboardViewModel

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Label("記録中", systemImage: "record.circle")
                    .foregroundStyle(.red)
                    .font(.caption.bold())
                Spacer()
                Text("\(min(viewModel.recordingIndex + 1, viewModel.recordingTargets.count)) / \(viewModel.recordingTargets.count)")
                    .font(.caption.monospacedDigit())
            }

            if viewModel.recordingKind == .phrases {
                phraseView
            } else {
                Text(display(currentTarget))
                    .font(.system(size: 56, weight: .bold, design: .monospaced))
            }

            HStack {
                Button("スキップ") { viewModel.skipRecordingTarget() }
                Spacer()
                Button("保存しないでやめる", role: .destructive) { viewModel.stopRecording(save: false) }
                Button("保存して終了") { viewModel.stopRecording(save: true) }
                    .buttonStyle(.borderedProminent)
            }
            .font(.caption)
            .buttonStyle(.bordered)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
    }

    private var currentTarget: String {
        viewModel.recordingIndex < viewModel.recordingTargets.count
            ? viewModel.recordingTargets[viewModel.recordingIndex] : ""
    }

    /// スペースは見えないので「␣」で表す
    private func display(_ s: String) -> String {
        s == " " ? "␣" : s
    }

    /// フレーズのとき: 前後の文字も見せ、今の文字を強調する
    private var phraseView: some View {
        let start = max(0, viewModel.recordingIndex - 8)
        let end = min(viewModel.recordingTargets.count, viewModel.recordingIndex + 12)
        let items = Array(start..<end)
        return items.reduce(Text("")) { result, i in
            let piece = Text(display(viewModel.recordingTargets[i]))
            if i == viewModel.recordingIndex {
                return result + piece.bold().underline().foregroundColor(.red)
            } else if i < viewModel.recordingIndex {
                return result + piece.foregroundColor(.secondary)
            }
            return result + piece
        }
        .font(.system(.title, design: .monospaced))
    }
}
