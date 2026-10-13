import Foundation

/// 膝モード / 机モード
enum KeyboardMode: String, Codable, CaseIterable, Identifiable {
    /// 膝の上で打つ。面がやわらかく(止まり方がゆるやか)、脚も動くので、判定をゆるめにする
    case knee
    /// 机の上で打つ。面が硬く(ピタッと止まる)、動かないので、判定を厳しめ・キー位置を固定にする
    case desk

    var id: String { rawValue }

    var japaneseName: String {
        switch self {
        case .knee: return "膝モード"
        case .desk: return "机モード"
        }
    }
}

/// キー配置を何に固定するか
enum LayoutAnchor: String, Codable, CaseIterable, Identifiable {
    /// 手の動きについていく(膝が動いてもずれにくい。ただし手ごと大きく動かしても同じキーのまま)
    case followHand
    /// キャリブレーションした場所に固定する(実物のキーボードに近い。カメラと面が動かないことが前提)
    case fixed

    var id: String { rawValue }

    var japaneseName: String {
        switch self {
        case .followHand: return "手に追従"
        case .fixed: return "面に固定"
        }
    }
}

/// キー配置の上に重ねて表示するもの
enum OverlayMode: String, Codable, CaseIterable, Identifiable {
    /// キーの枠と文字
    case keys
    /// 当たり判定ビュー: 各場所で「押したらどのキーになるか」(事後確率が最大のキー)で色分け
    case hitMap
    /// タッチヒートマップ: 実際に押した場所の分布(個人適応のデータ)
    case heatmap

    var id: String { rawValue }

    var japaneseName: String {
        switch self {
        case .keys: return "キー"
        case .hitMap: return "当たり判定"
        case .heatmap: return "ヒートマップ"
        }
    }
}

/// 機能の ON/OFF(あとで効果を比べるため、すべて設定画面で切り替えられるようにしている)
struct FeatureFlags: Codable, Equatable {
    /// タップ推定レベルA: カメラの急停止に加えて、マイクの音の立ち上がりを条件にする
    var audioOnset: Bool = true
    /// 加速度センサー(iPhone 本体の振動)も「当たった証拠」に使う(机に iPhone を置くとき向け)
    var motionAssist: Bool = false
    /// デコーダー: 位置の分布 × 指の制約 × 言語モデルでキーを選ぶ(オフなら最も近いキー)
    var decoder: Bool = true
    /// デコーダーで文字 n-gram 言語モデルを使う
    var languageModel: Bool = true
    /// 単語単位のビームサーチで、確定済みの文字をさかのぼって直す
    var wordDecoder: Bool = false
    /// 個人適応: 打ち直した箇所から、指ごとの押しがちなずれを学ぶ
    var personalAdaptation: Bool = false
    /// タップ推定レベルB: 学習モデル(Core ML)でタップかどうかを判定する(モデルを入れたときだけ)
    var levelBModel: Bool = false
    /// 机モードで、四隅の登録(ホモグラフィー)を使って真上から見た座標に直す
    var deskHomography: Bool = true
    /// 個人辞書: 確定した単語・言い回しを端末内に覚えて、言語モデルと単語の辞書に足す
    var personalDictionary: Bool = true
}

/// アプリの設定(UserDefaults に保存する)
///
/// 各プロパティに書いてある値は「土台の値」です。アプリの初回起動時は
/// `KeyboardSettings.defaults(for: .knee)` を使い、モードごとの初期値を当てはめます。
struct KeyboardSettings: Codable, Equatable {
    /// 膝モード / 机モード
    var mode: KeyboardMode = .knee

    /// 関節点の信頼度のしきい値。これより低い点は無視する。
    var minConfidence: Double = 0.3
    /// Vision の左右判定を入れ替える(左右が逆に認識されるとき用)
    var swapHands: Bool = false
    /// キー配置を手に追従させるときの「なめらかさ」(0: 追従が速い 〜 0.95: ゆっくり)
    var layoutSmoothing: Double = 0.7

    /// キーの大きさの倍率(1 = キャリブレーションで測った指の間隔どおり)
    var keyScale: Double = 1.0
    /// キー配置の基準
    var anchor: LayoutAnchor = .followHand
    /// 指ごとに担当キーを限定する(タッチタイピングの指の割り当て)
    var restrictKeysToFinger: Bool = true
    /// 指先からこれ以上離れたキーは押していないとみなす(キーの大きさ単位)
    var maxKeyDistance: Double = 1.3

    /// タップの感度(0〜1)。画面下のスライダーで実行中に変えられる。
    var sensitivity: Double = 0.5
    /// タップ判定のしきい値
    var tap = TapParameters()

    /// タップ時の触覚フィードバック
    var hapticsEnabled: Bool = true
    /// タップ時の効果音
    var soundEnabled: Bool = true

    /// 機能の ON/OFF
    var features = FeatureFlags()
    /// 手の追跡器(Vision / MediaPipe)
    var handTracker: HandTrackerKind = .vision
    /// センサー融合の時間窓など
    var fusion = FusionConfig()
    /// デコーダー(空間タッチモデル × 言語モデル)の設定
    var decoder = DecoderConfig()
    /// 個人適応の設定
    var adaptation = AdaptationConfig()
    /// 個人辞書
    var personalDictionary = PersonalDictionaryConfig()
    /// 単語単位のデコードの設定
    var wordDecoder = WordBeamDecoder.Config()
    /// 入力の方式(QWERTY / フリック)
    var inputMode: InputMode = .qwerty
    /// フリック入力の設定
    var flick = FlickConfig()
    /// レベルB: この確率より低い候補はタップにしない
    var levelBThreshold: Double = 0.5
    /// レベルB: 位置の補正を使う
    var levelBUseOffset: Bool = true
    /// キー配置の上に重ねて表示するもの
    var overlayMode: OverlayMode = .keys
    /// 机モードで登録する範囲の実際の大きさ(cm)。メジャーで測って入れると、キーの大きさが cm で分かる
    var deskWidthCm: Double = 60
    var deskDepthCm: Double = 40
    /// 音のオンセット検出の設定
    var audioOnset = OnsetDetectorConfig()
    /// 振動のオンセット検出の設定
    var motionOnset = OnsetDetectorConfig(k: 6, minSpread: 0.003, historyDuration: 0.5, refractory: 0.08)

    /// LiDAR の深度で「指が面に近づいたか」を確かめる(LiDAR 搭載機のみ)
    var useLiDAR: Bool = false
    /// 面に触れていたときの高さから、これ以上持ち上がっていたらタップにしない(メートル)
    var lidarTolerance: Double = 0.015

    /// デバッグ表示
    var showDebug: Bool = false
    /// デバッグ表示で速度グラフを出す指
    var debugFinger = FingerID(chirality: .right, finger: .index)

    /// 指定したモードの初期値で作った設定
    static func defaults(for mode: KeyboardMode) -> KeyboardSettings {
        var settings = KeyboardSettings()
        settings.applyModeDefaults(mode)
        return settings
    }

    /// モードを切り替え、「モードによって変わる値」をそのモードの初期値に戻す。
    /// (触覚・効果音・デバッグ表示などの好みの設定はそのまま残す)
    ///
    /// ★ 初期値はここにまとめています。実機で試して、よく合う値が見つかったらここを書き換えてください。
    mutating func applyModeDefaults(_ mode: KeyboardMode) {
        self.mode = mode
        switch mode {
        case .knee:
            keyScale = 1.15           // 膝は位置がぶれやすいので、キーを大きめに
            anchor = .followHand      // 脚が動いてもキーが手についてくるように
            maxKeyDistance = 1.5
            tap = TapParameters(
                downSpeed: 0.9,       // 布や脚はやわらかく、指の速さが出にくいので低め
                stopRatio: 0.45,      // やわらかい面では止まり方がゆるやかなので、ゆるめに
                minTravel: 0.05,
                maxDownDuration: 0.3,
                cooldown: 0.15,
                maxPalmSpeed: 2.0,    // 脚の揺れで手全体が動きやすいので、少し許容する
                smoothing: 0.35,
                sameHandLockout: 0.06,
                direction: .towardWrist)
        case .desk:
            keyScale = 1.0
            anchor = .fixed           // 机とカメラが動かない前提で、実物のキーボードのように固定
            maxKeyDistance = 1.3
            tap = TapParameters(
                downSpeed: 1.2,       // 硬い面では指が速く当たってピタッと止まる
                stopRatio: 0.35,
                minTravel: 0.06,
                maxDownDuration: 0.25,
                cooldown: 0.15,
                maxPalmSpeed: 1.5,
                smoothing: 0.3,
                sameHandLockout: 0.06,
                direction: .towardWrist)
        }
    }
}
