import SwiftUI

/// 設定画面。値を動かすと、次のフレームからすぐに判定へ反映されます。
struct SettingsView: View {
    @Bindable var viewModel: KeyboardViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                modeSection
                tapSection
                layoutSection
                feedbackSection
                calibrationSection
                debugSection
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    // MARK: - モード

    private var modeSection: some View {
        Section {
            // モードを変えると、そのモードの初期値(キーの大きさ・しきい値)に切り替わる
            Picker("モード", selection: Binding(
                get: { viewModel.settings.mode },
                set: { viewModel.setMode($0) }
            )) {
                ForEach(KeyboardMode.allCases) { mode in
                    Text(mode.japaneseName).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Button("このモードの初期値に戻す") {
                viewModel.resetToModeDefaults()
            }
        } header: {
            Text("モード")
        } footer: {
            Text("膝モード: キー大きめ・判定ゆるめ・キーが手に追従。\n机モード: 判定厳しめ・キーは面に固定。\nモードを切り替えると、下のしきい値はそのモードの初期値に戻ります。")
        }
    }

    // MARK: - タップ判定

    private var tapSection: some View {
        Section {
            ParameterSlider(title: "感度", value: $viewModel.settings.sensitivity, range: 0...1,
                            format: { "\(Int($0 * 100))" },
                            help: "下の「速さ」「移動量」のしきい値を 2倍(感度0)〜0.5倍(感度100)にします。")
            ParameterSlider(title: "下ろす速さのしきい値", value: $viewModel.settings.tap.downSpeed, range: 0.2...4,
                            format: { String(format: "%.2f 手/秒", $0) },
                            help: "これより速く指が下りたら「下ろし始め」。小さいほど敏感。")
            ParameterSlider(title: "止まりの判定(ピーク比)", value: $viewModel.settings.tap.stopRatio, range: 0.05...0.9,
                            format: { String(format: "%.2f", $0) },
                            help: "速さが最大値のこの割合まで落ちたら「面に当たった」。大きいほどゆるい止まり方でも反応。")
            ParameterSlider(title: "最小の移動量", value: $viewModel.settings.tap.minTravel, range: 0.01...0.3,
                            format: { String(format: "%.3f 手", $0) },
                            help: "これより小さい動きはタップにしない(手ぶれ対策)。")
            ParameterSlider(title: "下ろす時間の上限", value: $viewModel.settings.tap.maxDownDuration, range: 0.08...0.6,
                            format: { "\(Int($0 * 1000)) ms" },
                            help: "これより長くかかる動きはタップではない。")
            ParameterSlider(title: "クールダウン", value: $viewModel.settings.tap.cooldown, range: 0.05...0.5,
                            format: { "\(Int($0 * 1000)) ms" },
                            help: "同じ指の連続誤検出を防ぐ待ち時間。")
            ParameterSlider(title: "同じ手の別の指のロック", value: $viewModel.settings.tap.sameHandLockout, range: 0...0.2,
                            format: { "\(Int($0 * 1000)) ms" },
                            help: "隣の指がつられて動いたのを誤検出しないための時間。")
            ParameterSlider(title: "手全体の動きの上限", value: $viewModel.settings.tap.maxPalmSpeed, range: 0.3...5,
                            format: { String(format: "%.2f 手/秒", $0) },
                            help: "手ごとこれより速く動いている間は判定しない。")
            ParameterSlider(title: "平滑化", value: $viewModel.settings.tap.smoothing, range: 0...0.9,
                            format: { String(format: "%.2f", $0) },
                            help: "大きいほど震えに強いが、反応が遅れ、止まりも検出しにくくなる。")
            ParameterSlider(title: "信頼度のしきい値", value: $viewModel.settings.minConfidence, range: 0.05...0.9,
                            format: { String(format: "%.2f", $0) },
                            help: "Vision の自信がこれより低い点は使わない。")
            Picker("「下向き」の定義", selection: $viewModel.settings.tap.direction) {
                ForEach(TapDirection.allCases) { direction in
                    Text(direction.japaneseName).tag(direction)
                }
            }
        } header: {
            Text("タップ判定")
        } footer: {
            Text("単位の「手」は、手首から中指の付け根までの長さ(約9cm)です。調整の手順は README を見てください。")
        }
    }

    // MARK: - キー配置

    private var layoutSection: some View {
        Section {
            ParameterSlider(title: "キーの大きさ", value: $viewModel.settings.keyScale, range: 0.6...1.8,
                            format: { String(format: "×%.2f", $0) },
                            help: "キャリブレーションで測った指の間隔に対する倍率。")
            Picker("キー配置の基準", selection: $viewModel.settings.anchor) {
                ForEach(LayoutAnchor.allCases) { anchor in
                    Text(anchor.japaneseName).tag(anchor)
                }
            }
            Toggle("指の担当キーだけから選ぶ", isOn: $viewModel.settings.restrictKeysToFinger)
            ParameterSlider(title: "キーとみなす距離", value: $viewModel.settings.maxKeyDistance, range: 0.6...3,
                            format: { String(format: "%.1f キー", $0) },
                            help: "指先からこれより遠いキーは押していないとみなす。")
            ParameterSlider(title: "キー配置のなめらかさ", value: $viewModel.settings.layoutSmoothing, range: 0...0.95,
                            format: { String(format: "%.2f", $0) },
                            help: "「手に追従」のとき、キーがどれだけゆっくり手についてくるか。")
            Toggle("左右の手を入れ替える", isOn: $viewModel.settings.swapHands)
        } header: {
            Text("キー配置")
        } footer: {
            Text("手に追従: 膝が動いてもずれにくい。面に固定: 実物のキーボードに近いが、カメラや面が動いたら再キャリブレーションが必要。\n左右が逆に表示される(左手が右手の色)ときは「入れ替える」をオンに。")
        }
    }

    // MARK: - キャリブレーション

    private var calibrationSection: some View {
        Section {
            if let calibration = viewModel.calibration {
                LabeledContent("保存日時", value: calibration.createdAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("キー間隔(左/右)",
                               value: String(format: "%.2f / %.2f 手", calibration.left.keyPitch, calibration.right.keyPitch))
                LabeledContent("奥行きの縮み(左/右)",
                               value: String(format: "%.2f / %.2f", calibration.left.foreshortening, calibration.right.foreshortening))
                Button("保存したキャリブレーションを削除", role: .destructive) {
                    viewModel.deleteCalibration()
                }
            } else {
                Text("まだキャリブレーションしていません")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("キャリブレーション")
        } footer: {
            Text("キャリブレーションの結果は保存され、次回の起動時にも使われます。カメラの位置や姿勢を変えたら、やり直してください。")
        }
    }

    // MARK: - デバッグ

    private var debugSection: some View {
        Section {
            Toggle("デバッグ表示", isOn: $viewModel.settings.showDebug)
            Picker("速度グラフに出す指", selection: $viewModel.settings.debugFinger) {
                ForEach(FingerID.all) { finger in
                    Text(finger.japaneseName).tag(finger)
                }
            }
        } header: {
            Text("デバッグ")
        } footer: {
            Text("グラフの白線が赤い点線(しきい値)を超えると「下ろし中」(黄色の点)になり、急に下がった瞬間に緑の縦線(タップ)が出ます。")
        }
    }

    // MARK: - フィードバック

    private var feedbackSection: some View {
        Section("フィードバック") {
            Toggle("触覚フィードバック", isOn: $viewModel.settings.hapticsEnabled)
            Toggle("効果音(消音モードでは鳴りません)", isOn: $viewModel.settings.soundEnabled)
        }
    }
}

/// 「名前・今の値・スライダー・説明」をまとめた部品
struct ParameterSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var format: (Double) -> String = { String(format: "%.2f", $0) }
    var help: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(format(value))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range)
            if let help {
                Text(help)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
