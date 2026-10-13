import SwiftUI

/// 画面下の操作バー(感度スライダー、キャリブレーション、練習、デバッグ、設定)。
struct ControlBarView: View {
    /// @Bindable を付けると、@Observable なクラスのプロパティを
    /// `$viewModel.settings.sensitivity` のように Binding(双方向の結びつき)として渡せます。
    @Bindable var viewModel: KeyboardViewModel
    let onOpenSettings: () -> Void
    /// 記録の課題を選ぶダイアログを出しているか
    @State private var isChoosingRecording = false

    var body: some View {
        VStack(spacing: 10) {
            // 感度スライダー(実行中に動かすと、次のフレームから判定に反映されます)
            HStack {
                Image(systemName: "tortoise")
                Slider(value: $viewModel.settings.sensitivity, in: 0...1)
                Image(systemName: "hare")
                VStack(alignment: .trailing, spacing: 0) {
                    Text("感度 \(Int(viewModel.settings.sensitivity * 100))")
                        .font(.caption.monospacedDigit())
                    Text(viewModel.settings.mode.japaneseName)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 60, alignment: .trailing)
            }

            HStack {
                Button {
                    viewModel.startCalibration()
                } label: {
                    Label(viewModel.calibration == nil ? "キャリブレーション" : "再キャリブレーション",
                          systemImage: "hand.raised")
                        // 画面が狭い機種でも1行に収まるよう、必要なら文字を少し縮める
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isCalibrating)

                Spacer()

                // 記録モード(データ収集)
                Button {
                    if viewModel.isRecording {
                        viewModel.stopRecording(save: true)
                    } else {
                        isChoosingRecording = true
                    }
                } label: {
                    Image(systemName: viewModel.isRecording ? "stop.circle.fill" : "record.circle")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("記録モード")
                .confirmationDialog("記録する課題", isPresented: $isChoosingRecording, titleVisibility: .visible) {
                    Button("1文字ずつ(50文字)") { viewModel.startRecording(kind: .keys, count: 50) }
                    Button("1文字ずつ(150文字)") { viewModel.startRecording(kind: .keys, count: 150) }
                    Button("フレーズ(3文)") { viewModel.startRecording(kind: .phrases, count: 3) }
                    Button("仮名(フリック・20語)") { viewModel.startRecording(kind: .kana, count: 20) }
                    Button("やめる", role: .cancel) {}
                } message: {
                    Text("表示された文字を、このキーボードで打ってください。手の関節の座標・音・加速度と、目標の文字が保存されます(映像は保存しません)。")
                }

                // 練習モードの開始/終了
                Button {
                    if viewModel.practice == nil {
                        viewModel.startPractice()
                    } else {
                        viewModel.stopPractice()
                    }
                } label: {
                    Image(systemName: viewModel.practice == nil ? "graduationcap" : "graduationcap.fill")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("練習モード")

                // デバッグ表示の切り替え(てんとう虫=「バグ」のアイコン)
                Toggle(isOn: $viewModel.settings.showDebug) {
                    Image(systemName: "ladybug")
                }
                .toggleStyle(.button)
                .accessibilityLabel("デバッグ表示")

                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape")
                        .font(.title3)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("設定")
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}
