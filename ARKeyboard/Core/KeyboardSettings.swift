import Foundation

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

/// アプリの設定(UserDefaults に保存する)
struct KeyboardSettings: Codable, Equatable {
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
    /// デバッグ表示で速度グラフを出す指
    var debugFinger = FingerID(chirality: .right, finger: .index)
}
