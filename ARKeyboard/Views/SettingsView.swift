import SwiftUI

/// 設定画面。値を動かすと、次のフレームからすぐに判定へ反映されます。
struct SettingsView: View {
    @Bindable var viewModel: KeyboardViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                modeSection
                trackerSection
                if viewModel.settings.mode == .desk {
                    deskSection
                }
                inputModeSection
                if viewModel.settings.inputMode == .flick {
                    flickSection
                }
                if viewModel.settings.inputMode == .handwriting {
                    handwritingSection
                }
                tapSection
                sensorSection
                levelBSection
                decoderSection
                adaptationSection
                personalDictionarySection
                layoutSection
                feedbackSection
                // LiDAR が無い機種では、この設定自体を出さない
                if DepthCameraManager.isSupported {
                    lidarSection
                }
                calibrationSection
                recordingsSection
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

    // MARK: - 入力方式(QWERTY / フリック)

    private var inputModeSection: some View {
        Section {
            Picker("入力方式", selection: $viewModel.settings.inputMode) {
                ForEach(InputMode.allCases) { mode in
                    Text(mode.japaneseName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("入力方式")
        } footer: {
            Text("フリック(比較実験用): 片手に 12 キーの仮名パッド、もう一方の手に機能パッド(空白・削除など)を置きます。\n手書き: 人差し指と親指でつまんだまま書き、指を離して 1 秒たつと文字を認識します。もう一方の手は機能パッドです。")
        }
    }

    private var flickSection: some View {
        Section {
            Picker("フリックパッドの手", selection: $viewModel.settings.flick.hand) {
                Text("右手").tag(Chirality.right)
                Text("左手").tag(Chirality.left)
            }
            Toggle("両手ともフリックパッド", isOn: $viewModel.settings.flick.bothHands)
            Picker("切り出し方", selection: $viewModel.settings.flick.segmentation) {
                ForEach(FlickSegmentation.allCases) { s in
                    Text(s.japaneseName).tag(s)
                }
            }
            ParameterSlider(title: "キーの大きさ", value: $viewModel.settings.flick.keyScale, range: 0.8...3,
                            format: { String(format: "×%.2f", $0) })
            ParameterSlider(title: "動き出しの速さ", value: $viewModel.settings.flick.startSpeed, range: 0.5...5,
                            format: { String(format: "%.2f 手/秒", $0) },
                            help: "これより速く動いたらフリックの始まり。キーの上への移動を誤ってフリックにするなら上げる")
            ParameterSlider(title: "止まりの速さ", value: $viewModel.settings.flick.endSpeed, range: 0.1...2,
                            format: { String(format: "%.2f 手/秒", $0) })
            ParameterSlider(title: "動き出す前の静止", value: $viewModel.settings.flick.dwellTime, range: 0...0.3,
                            format: { String(format: "%.0f ms", $0 * 1000) })
            ParameterSlider(title: "フリックの最長時間", value: $viewModel.settings.flick.maxDuration, range: 0.15...1,
                            format: { String(format: "%.0f ms", $0 * 1000) })
            ParameterSlider(title: "フリックの最大距離", value: $viewModel.settings.flick.maxDistance, range: 0.2...1.5,
                            format: { String(format: "%.2f 手", $0) })
            ParameterSlider(title: "タップとみなす距離", value: $viewModel.settings.flick.tapDistance, range: 0.02...0.3,
                            format: { String(format: "%.2f 手", $0) })
            ParameterSlider(title: "方向の鋭さ κ", value: $viewModel.settings.flick.kappa, range: 0.5...10,
                            format: { String(format: "%.1f", $0) },
                            help: "大きいほど、測った向きをそのまま信じる。小さいほど文脈(言語モデル)に頼る")
            Toggle("ぶれ除去フィルター(One Euro)", isOn: $viewModel.settings.flick.useJitterFilter)
            if viewModel.settings.flick.useJitterFilter {
                ParameterSlider(title: "止まっているときの遮断周波数", value: $viewModel.settings.flick.filterMinCutoff,
                                range: 0.3...5, format: { String(format: "%.1f Hz", $0) },
                                help: "小さいほど震えが消えるが、動き出しに遅れる。オンにしたら「動き出しの速さ」を 1.2 程度に下げる")
                ParameterSlider(title: "速さに応じた追従", value: $viewModel.settings.flick.filterBeta, range: 0...10,
                                format: { String(format: "%.1f", $0) })
            }
            Toggle("仮名の言語モデル", isOn: $viewModel.settings.flick.useLanguageModel)
            if viewModel.settings.flick.useLanguageModel {
                ParameterSlider(title: "言語モデルの重み", value: $viewModel.settings.flick.lmWeight, range: 0...2)
            }
            if !viewModel.settings.flick.bothHands {
                ForEach(Finger.allCases, id: \.self) { finger in
                    Picker("機能パッド: \(finger.japaneseName)", selection: Binding(
                        get: { viewModel.settings.flick.action(for: finger) },
                        set: { viewModel.settings.flick.functionMapping[finger.rawValue] = $0 }
                    )) {
                        ForEach(FunctionAction.allCases) { action in
                            Text(action.japaneseName).tag(action)
                        }
                    }
                }
            }
        } header: {
            Text("フリック")
        } footer: {
            Text("数値はすべて仮説です(実機の記録で調整してください)。黄色の扇形は、文脈から見た各方向の出やすさ = 実効的な判定範囲の広さです。")
        }
    }

    private var handwritingSection: some View {
        Section {
            Picker("書く手", selection: $viewModel.settings.handwriting.hand) {
                Text("右手").tag(Chirality.right)
                Text("左手").tag(Chirality.left)
            }
            Picker("言語", selection: $viewModel.settings.handwriting.language) {
                Text("日本語").tag("ja-JP")
                Text("英語").tag("en-US")
            }
            Toggle("1位の候補を自動で入力", isOn: $viewModel.settings.handwriting.autoInsert)
            Toggle("左右反転(鏡文字になるとき)", isOn: $viewModel.settings.handwriting.mirror)
            ParameterSlider(title: "ペンを下ろす距離", value: $viewModel.settings.handwriting.pinchDown, range: 0.1...0.5,
                            format: { String(format: "%.2f 手", $0) },
                            help: "親指の先と人差し指の先がこれより近づいたら、書き始める")
            ParameterSlider(title: "ペンを上げる距離", value: $viewModel.settings.handwriting.pinchUp, range: 0.15...0.7,
                            format: { String(format: "%.2f 手", $0) })
            ParameterSlider(title: "書き終わりの待ち時間", value: $viewModel.settings.handwriting.finishDelay, range: 0.3...3,
                            format: { String(format: "%.1f 秒", $0) })
        } header: {
            Text("手書き")
        } footer: {
            Text("文字の向きは手の向き(手首→指先が上)で決めます。画像の上下左右は使いません。文字認識は Vision で端末の中だけで行います。")
        }
    }

    // MARK: - 手の追跡器

    private var trackerSection: some View {
        Section {
            Picker("手の追跡", selection: $viewModel.settings.handTracker) {
                ForEach(HandTrackerKind.allCases) { kind in
                    Text(kind.japaneseName + (HandTrackerFactory.isAvailable(kind) ? "" : "(未導入)")).tag(kind)
                }
            }
            LabeledContent("使用中", value: viewModel.activeTracker.japaneseName)
            ForEach(HandTrackerKind.allCases) { kind in
                if let stats = viewModel.trackerStats[kind] {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(kind.japaneseName).font(.caption.bold())
                        Text(String(format: "FPS %.0f / 処理 %.1f ms / 両手の検出 %.0f%% / ぶれ %.4f 手",
                                    stats.fps, stats.processingMs, stats.twoHandRate * 100, stats.jitter))
                            .font(.caption.monospacedDigit())
                    }
                }
            }
        } header: {
            Text("手の追跡")
        } footer: {
            Text("Vision は標準で使えます(2D)。MediaPipe(3D)は導入が必要です(README 参照)。切り替えて同じように手を止めたときの「ぶれ」と、FPS・両手の検出率を比べてください。")
        }
    }

    // MARK: - 机モード(四隅の登録)

    private var deskSection: some View {
        Section {
            Toggle("四隅の登録(ホモグラフィー)を使う", isOn: $viewModel.settings.features.deskHomography)
            ParameterSlider(title: "登録する範囲の幅", value: $viewModel.settings.deskWidthCm, range: 20...120,
                            format: { "\(Int($0)) cm" })
            ParameterSlider(title: "登録する範囲の奥行き", value: $viewModel.settings.deskDepthCm, range: 10...80,
                            format: { "\(Int($0)) cm" })
            Button(viewModel.deskPlane == nil ? "机の四隅を登録する" : "机の四隅を登録し直す") {
                dismiss()
                viewModel.startDeskRegistration()
            }
            if viewModel.deskPlane != nil {
                Button("登録した四隅を削除", role: .destructive) {
                    viewModel.deleteDeskPlane()
                }
            }
        } header: {
            Text("机モード: 四隅の登録")
        } footer: {
            Text("カメラが机を斜めから見ていると、奥は小さく手前は大きく映ります。机の四隅(またはテープで貼った長方形の四隅)を登録すると、真上から見た座標に直して計算します。登録し直すとキャリブレーションもやり直しになります。膝モードでは使いません(膝は平らでないため)。")
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
                            help: "同じ指の連続誤検出を防ぐ待ち時間(入力が採用された後に掛かる)。")
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

    // MARK: - センサーと二重条件(タップ推定レベルA)

    private var sensorSection: some View {
        Section {
            Toggle("音の立ち上がりを条件にする(マイク)", isOn: $viewModel.settings.features.audioOnset)
            if viewModel.settings.features.audioOnset {
                LabeledContent("マイクの状態", value: viewModel.audioStatus)
                ParameterSlider(title: "音の感度(k)", value: $viewModel.settings.audioOnset.k, range: 2...15,
                                format: { String(format: "%.1f", $0) },
                                help: "しきい値 = 直近の中央値 + k × ばらつき。小さいほど小さな音にも反応(雑音にも反応しやすい)。")
            }
            Toggle("本体の振動も証拠にする(加速度)", isOn: $viewModel.settings.features.motionAssist)
            if viewModel.settings.features.motionAssist {
                LabeledContent("加速度センサーの状態", value: viewModel.motionStatus)
                ParameterSlider(title: "振動の感度(k)", value: $viewModel.settings.motionOnset.k, range: 2...15,
                                format: { String(format: "%.1f", $0) },
                                help: "iPhone をタップする面と同じ机に置いたときに有効です。")
            }
            ParameterSlider(title: "時間窓(カメラより前)", value: $viewModel.settings.fusion.windowBefore, range: 0...0.3,
                            format: { "\(Int($0 * 1000)) ms" },
                            help: "カメラが止まりを見つけたコマより、どれだけ前の音まで対応づけるか。")
            ParameterSlider(title: "時間窓(カメラより後)", value: $viewModel.settings.fusion.windowAfter, range: 0...0.3,
                            format: { "\(Int($0 * 1000)) ms" },
                            help: "デバッグ表示のタップログの「音±○ms」を見て、ほとんどが窓に入るように合わせます。")
            ParameterSlider(title: "音を待つ最大時間", value: $viewModel.settings.fusion.maxWait, range: 0.1...1.0,
                            format: { "\(Int($0 * 1000)) ms" },
                            help: "音のデータが遅れているとき、これ以上は待たずにカメラだけで決める。")
        } header: {
            Text("センサーと二重条件(レベルA)")
        } footer: {
            Text("カメラの「指が下りて急に止まった」と、マイクの「叩いた音の立ち上がり」が同じ頃に起きたときだけ入力します(Acustico の二重条件の考え方)。マイクが使えないときはカメラだけで判定します。")
        }
    }

    // MARK: - タップ推定レベルB(学習モデル)

    private var levelBSection: some View {
        Section {
            Toggle("学習モデルで判定する", isOn: $viewModel.settings.features.levelBModel)
            LabeledContent("モデル", value: viewModel.levelBModelStatus)
            ParameterSlider(title: "タップとみなす確率", value: $viewModel.settings.levelBThreshold, range: 0.1...0.95,
                            format: { "\(Int($0 * 100))%" })
            Toggle("位置の補正を使う", isOn: $viewModel.settings.levelBUseOffset)
        } header: {
            Text("タップ推定レベルB(学習モデル)")
        } footer: {
            Text("記録データから学習した小さなニューラルネットワーク(Core ML)で、カメラの候補が本当のタップかを判定し、位置も補正します。オンにすると、音が無い候補も一度モデルに渡します(採否はモデルが決める)。モデルは tools/eval/train_levelb.py で作り、ARKeyboard/Resources/Model/ に置いてください。")
        }
    }

    // MARK: - デコーダー(空間タッチモデル × 言語モデル)

    private var decoderSection: some View {
        Section {
            Toggle("デコーダーを使う", isOn: $viewModel.settings.features.decoder)
            if viewModel.settings.features.decoder {
                Toggle("文字 n-gram 言語モデルを使う", isOn: $viewModel.settings.features.languageModel)
                Picker("言語", selection: $viewModel.settings.decoder.language) {
                    ForEach(DecoderLanguage.allCases) { language in
                        Text(language.japaneseName).tag(language)
                    }
                }
                Stepper("n-gram の n: \(viewModel.settings.decoder.lmOrder)",
                        value: $viewModel.settings.decoder.lmOrder, in: 1...8)
                ParameterSlider(title: "言語モデルの重み w", value: $viewModel.settings.decoder.lmWeight, range: 0...3,
                                format: { String(format: "%.2f", $0) },
                                help: "大きいほど文脈を重視する。0 で位置だけ。")
                ParameterSlider(title: "アンカーの大きさ", value: $viewModel.settings.decoder.anchorFraction, range: 0...0.9,
                                format: { "\(Int($0 * 100))%" },
                                help: "キーの中央のこの割合の範囲は、文脈に関係なく必ずそのキーになる。0 で無効。")
                ParameterSlider(title: "キーごとのばらつき", value: $viewModel.settings.decoder.keySigma, range: 0.1...0.8,
                                format: { String(format: "%.2f キー", $0) },
                                help: "狙ったキーのまわりに、どれくらい散らばって押すかの見積もり(初期値)。")
                ParameterSlider(title: "カメラの測定のばらつき", value: $viewModel.settings.decoder.measurementSigma, range: 0...0.8,
                                format: { String(format: "%.2f キー", $0) },
                                help: "カメラで測った指先の位置の誤差の見積もり。")
                ParameterSlider(title: "担当外の指の罰点", value: $viewModel.settings.decoder.offFingerPenalty, range: 0...10,
                                format: { String(format: "%.1f", $0) },
                                help: "「指の担当キーだけから選ぶ」をオフにしたとき、担当外のキーをどれだけ選びにくくするか。")
                Toggle("単語単位で決め直す(ビームサーチ)", isOn: $viewModel.settings.features.wordDecoder)
                if viewModel.settings.features.wordDecoder {
                    Stepper("ビームの幅: \(viewModel.settings.wordDecoder.beamWidth)",
                            value: $viewModel.settings.wordDecoder.beamWidth, in: 1...32)
                    ParameterSlider(title: "辞書に無い綴りの罰点", value: $viewModel.settings.wordDecoder.lexiconPenalty,
                                    range: 0...8, format: { String(format: "%.1f", $0) },
                                    help: "学習用テキストの単語の頭にならない綴りを、どれだけ選びにくくするか。")
                }
                Toggle("入力の速さに合わせる", isOn: $viewModel.settings.decoder.speedAdaptation)
                if viewModel.settings.decoder.speedAdaptation {
                    ParameterSlider(title: "速いときのばらつきの増え方", value: $viewModel.settings.decoder.fastSigmaGain, range: 0...2,
                                    format: { String(format: "+%.0f%%", $0 * 100) })
                    ParameterSlider(title: "速いときの言語モデルの増え方", value: $viewModel.settings.decoder.fastLMGain, range: 0...2,
                                    format: { String(format: "+%.0f%%", $0 * 100) })
                }
                Picker("重ねる表示", selection: $viewModel.settings.overlayMode) {
                    ForEach(OverlayMode.allCases) { mode in
                        Text(mode.japaneseName).tag(mode)
                    }
                }
            }
        } header: {
            Text("デコーダー(空間タッチモデル)")
        } footer: {
            Text("キーを「確率の場」として扱い、位置の確率 × 文脈の確率 で最も確からしいキーを選びます(Goodman ら 2002、Gunawardana ら 2010)。「当たり判定」表示にすると、文脈で各キーの領域が広がる様子が見えます。")
        }
    }

    // MARK: - 個人適応とヒートマップ

    private var personalDictionarySection: some View {
        Section {
            Toggle("個人辞書を使う", isOn: $viewModel.settings.features.personalDictionary)
            LabeledContent("覚えた単語の数", value: "\(viewModel.personalWordCount)")
            ParameterSlider(title: "混ぜる重みの上限", value: $viewModel.settings.personalDictionary.weight, range: 0...0.8,
                            format: { String(format: "%.2f", $0) },
                            help: "よく打つ文脈ほど、この値に近い重みで個人の言語モデルを混ぜる")
            Button("個人辞書を消す", role: .destructive) {
                viewModel.resetPersonalDictionary()
            }
        } header: {
            Text("個人辞書")
        } footer: {
            Text("空白・改行・句読点で確定した単語と言い回しを、端末の中だけに覚えます(外部に送信しません。練習モード中は覚えません)。英字とかな、それぞれ最大 5000 文字。")
        }
    }

    private var adaptationSection: some View {
        Section {
            Toggle("個人適応を使う", isOn: $viewModel.settings.features.personalAdaptation)
            LabeledContent("学習したタップの数", value: "\(viewModel.adaptationSampleCount)")
            ParameterSlider(title: "初期値の強さ", value: $viewModel.settings.adaptation.priorStrength, range: 1...100,
                            format: { "\(Int($0)) 回分" },
                            help: "この回数分のタップが集まるまでは、初期値(ずれ 0)の影響が大きく残る。小さいほど早く学ぶが、ぶれやすい。")
            ParameterSlider(title: "ずれの上限", value: $viewModel.settings.adaptation.maxOffset, range: 0.1...1.0,
                            format: { String(format: "%.2f キー", $0) })
            ParameterSlider(title: "学習に使う確信度の下限", value: $viewModel.settings.adaptation.minPosterior, range: 0.5...0.99,
                            format: { "\(Int($0 * 100))%" })
            Button("学習データを消す", role: .destructive) {
                viewModel.resetAdaptation()
            }
        } header: {
            Text("個人適応とヒートマップ")
        } footer: {
            Text("確信度の高い入力と、削除して打ち直した箇所から、指×キーごとの「押しがちなずれ」を端末の中だけで学習します(外部に送信しません)。重ねる表示を「ヒートマップ」にすると、実際に押した場所が見えます。")
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

    // MARK: - LiDAR

    private var lidarSection: some View {
        Section {
            Toggle("LiDAR で接触を確認する", isOn: $viewModel.settings.useLiDAR)
            ParameterSlider(title: "面からの高さの許容量", value: $viewModel.settings.lidarTolerance, range: 0.005...0.05,
                            format: { String(format: "%.1f cm", $0 * 100) },
                            help: "タップの瞬間、指先が「面に触れていたときの高さ」よりこれ以上浮いていたら入力しない。")
            if viewModel.settings.useLiDAR && viewModel.calibration?.restRelativeDepths == nil {
                Text("LiDAR をオンにした状態で、もう一度キャリブレーションしてください(面に触れたときの深さを記録します)。")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("LiDAR(深度)")
        } footer: {
            Text("オンにするとカメラが ARKit に切り替わります。空中で指を止めただけの誤入力を減らせます。")
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

    // MARK: - 記録データ

    private var recordingsSection: some View {
        Section {
            if viewModel.savedRecordings.isEmpty {
                Text("まだ記録はありません。画面下の赤い丸のボタンで記録できます。")
                    .foregroundStyle(.secondary)
            }
            ForEach(viewModel.savedRecordings, id: \.self) { url in
                HStack {
                    Text(url.lastPathComponent)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                    Spacer()
                    // 共有シート(AirDrop で Mac に送る、「ファイル」に保存する など)
                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderless)
                }
                .swipeActions {
                    Button("削除", role: .destructive) { viewModel.deleteRecording(url) }
                }
            }
        } header: {
            Text("記録データ")
        } footer: {
            Text("記録は端末の中(「ファイル」アプリ → このiPhone内 → ARKeyboard → Recordings)に保存されます。外部には送信しません。Mac の tools/eval/ で評価します(README 参照)。")
        }
        .onAppear { viewModel.refreshRecordings() }
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
