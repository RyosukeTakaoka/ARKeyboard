import Foundation

/// 1つの (指, キー) の組の「タップ位置の分布」(2変量ガウス分布)
struct KeyGaussian: Codable, Equatable {
    /// キーの中心からのずれ(平均。キー配置の座標の単位)
    var offset: Vec2
    /// ばらつき(共分散)
    var covariance: Covariance2
    /// これまでに学習したタップの数(個人適応で使う。初期値は 0)
    var count: Double
}

/// 空間タッチモデル: キーを「四角い領域」ではなく「確率の場」として扱う。
///
/// 指 f でキー k を狙ったとき、位置 x に触れる確率 p(x | k, f) を、2変量ガウス分布で表します。
/// - 平均 = キーの中心 + その (指, キー) に特有のずれ
/// - 共分散 = その (指, キー) に特有のばらつき
///
/// 学習前(初期値)は「ずれ 0、ばらつきはキーの大きさに比例」。
/// 個人適応(Tier2)で、利用者の押し方に合わせて (指, キー) ごとに更新されます。
/// 更新は Gunawardana ら(IUI 2010)と同じく、共役事前分布による MAP 推定(縮小推定)で行う予定で、
/// データが少ない間は初期値に引き寄せられます。
final class SpatialTouchModel {
    /// 初期値のばらつき(キーの大きさに対する割合。標準偏差)
    var priorSigmaFraction: Double = 0.3

    /// 学習済みの分布。キーは "指のID|キーのID"
    private(set) var learned: [String: KeyGaussian] = [:]

    static func storageKey(finger: FingerID?, key: Key) -> String {
        "\(finger?.id ?? "any")|\(key.id)"
    }

    /// 初期値(学習前)の分布
    func prior(for key: Key) -> KeyGaussian {
        KeyGaussian(offset: .zero,
                    covariance: .diagonal(sigmaX: priorSigmaFraction * key.size.x,
                                          sigmaY: priorSigmaFraction * key.size.y),
                    count: 0)
    }

    /// (指, キー) の分布(学習済みならそれ、無ければ初期値)
    func gaussian(for key: Key, finger: FingerID?) -> KeyGaussian {
        learned[Self.storageKey(finger: finger, key: key)] ?? prior(for: key)
    }

    /// 学習済みの分布をまとめて入れ替える(保存データの読み込み、個人適応から使う)
    func setLearned(_ values: [String: KeyGaussian]) {
        learned = values
    }

    func setLearned(_ value: KeyGaussian, for key: Key, finger: FingerID?) {
        learned[Self.storageKey(finger: finger, key: key)] = value
    }

    func resetLearned() {
        learned.removeAll()
    }

    /// log p(位置 | キー, 指)
    /// - Parameters:
    ///   - location: タップ位置(キー配置の座標)
    ///   - measurementCovariance: 測定そのものの不確かさ(TouchEvent の共分散)。分布の広がりに足し合わせる
    ///   - sigmaScale: ばらつきを何倍に見積もるか(入力が速いときは大きくする)
    func logLikelihood(of location: Vec2, key: Key, finger: FingerID?,
                       measurementCovariance: Covariance2, sigmaScale: Double) -> Double {
        let g = gaussian(for: key, finger: finger)
        let s2 = sigmaScale * sigmaScale
        let covariance = Covariance2(xx: g.covariance.xx * s2, xy: g.covariance.xy * s2, yy: g.covariance.yy * s2)
            + measurementCovariance
        return covariance.logDensity(of: location - (key.center + g.offset))
    }
}
