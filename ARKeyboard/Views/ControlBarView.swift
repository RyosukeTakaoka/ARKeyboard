import SwiftUI

/// 画面下の操作バー(感度スライダー、キャリブレーション、モード表示、設定)。
struct ControlBarView: View {
    /// @Bindable を付けると、@Observable なクラスのプロパティを
    /// `$viewModel.settings.sensitivity` のように Binding(双方向の結びつき)として渡せます。
    @Bindable var viewModel: KeyboardViewModel
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            // 感度スライダー(実行中に動かすと、次のフレームから判定に反映されます)
            HStack {
                Image(systemName: "tortoise")
                Slider(value: $viewModel.settings.sensitivity, in: 0...1)
                Image(systemName: "hare")
                Text("感度 \(Int(viewModel.settings.sensitivity * 100))")
                    .font(.caption.monospacedDigit())
                    .frame(width: 60, alignment: .trailing)
            }

            HStack {
                Button {
                    viewModel.startCalibration()
                } label: {
                    Label(viewModel.calibration == nil ? "キャリブレーション" : "再キャリブレーション",
                          systemImage: "hand.raised")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isCalibrating)

                Spacer()

                Text(viewModel.settings.mode.japaneseName)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.thinMaterial, in: Capsule())

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
