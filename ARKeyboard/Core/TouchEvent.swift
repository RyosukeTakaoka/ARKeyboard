import Foundation

/// 2x2 の共分散行列(2変量ガウス分布の「広がり方」)
///
/// ```
///  | xx  xy |
///  | xy  yy |
/// ```
/// - xx: 横方向のばらつき(分散)、yy: 縦方向のばらつき、xy: 斜めの相関(共分散)。
/// TouchInsight や Goodman らの研究のように、触れた位置を「点」ではなく「分布」として持つために使う。
struct Covariance2: Codable, Equatable {
    var xx: Double
    var xy: Double
    var yy: Double

    /// 縦横同じばらつき(標準偏差 sigma)の円形の分布
    static func isotropic(sigma: Double) -> Covariance2 {
        Covariance2(xx: sigma * sigma, xy: 0, yy: sigma * sigma)
    }

    /// 横と縦で違うばらつき
    static func diagonal(sigmaX: Double, sigmaY: Double) -> Covariance2 {
        Covariance2(xx: sigmaX * sigmaX, xy: 0, yy: sigmaY * sigmaY)
    }

    var determinant: Double { xx * yy - xy * xy }

    static func + (a: Covariance2, b: Covariance2) -> Covariance2 {
        Covariance2(xx: a.xx + b.xx, xy: a.xy + b.xy, yy: a.yy + b.yy)
    }

    /// 2変量ガウス分布の確率密度の対数 log N(d; 0, Σ)。
    /// 確率の掛け算を「対数の足し算」にすると、小さな数を掛け続けても 0 に潰れない(アンダーフローしない)。
    func logDensity(of d: Vec2) -> Double {
        let det = max(determinant, 1e-12)
        // Σ の逆行列を使った「マハラノビス距離」の2乗 = dᵀ Σ⁻¹ d
        let mahalanobis = (yy * d.x * d.x - 2 * xy * d.x * d.y + xx * d.y * d.y) / det
        return -0.5 * mahalanobis - log(2 * Double.pi) - 0.5 * log(det)
    }
}

/// どのセンサーがタップを裏付けたか
enum TouchEvidence: String, Codable, CaseIterable, Hashable {
    /// カメラ(指が下りて急停止した)
    case vision
    /// マイク(音の立ち上がり)
    case audio
    /// 加速度センサー(iPhone 本体の振動)
    case motion
    /// LiDAR(指が面の高さまで下りていた)
    case depth
}

/// タップイベント(TouchInsight 型: 「いつ・どの指・どこ」と、その確からしさ)
struct TouchEvent: Codable, Equatable {
    /// 触れた時刻(秒)
    var time: Double
    /// どの指か
    var finger: FingerID
    /// 触れた位置(キー配置の座標 = 手の座標。x: 親指側+, y: 前+)
    var surfaceLocation: Vec2
    /// 位置の不確かさ(2変量ガウス分布の共分散。キー配置の座標の単位)
    var locationCovariance: Covariance2
    /// タップである確からしさ(0〜1)
    var confidence: Double
    /// 画像上の指先の位置(ピクセル。記録・デバッグ用)
    var imagePosition: Vec2
    /// 裏付けたセンサー
    var evidence: Set<TouchEvidence>
}
