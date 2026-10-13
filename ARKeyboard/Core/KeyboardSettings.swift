import Foundation

/// アプリの設定(UserDefaults に保存する)
struct KeyboardSettings: Codable, Equatable {
    /// 関節点の信頼度のしきい値。これより低い点は無視する。
    var minConfidence: Double = 0.3
    /// Vision の左右判定を入れ替える(左右が逆に認識されるとき用)
    var swapHands: Bool = false
    /// キー配置を手に追従させるときの「なめらかさ」(0: 追従が速い 〜 0.95: ゆっくり)
    var layoutSmoothing: Double = 0.7
}
