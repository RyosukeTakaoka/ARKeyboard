import Foundation

/// 個人適応の設定
struct AdaptationConfig: Codable, Equatable {
    /// 事前分布の強さ(「何回分のタップに相当する自信で初期値を信じるか」)。大きいほど学習がゆっくり
    var priorStrength: Double = 15
    /// ずれの大きさの上限(キーの大きさ単位)。おかしなデータで、キーが大きくずれてしまうのを防ぐ
    var maxOffset: Double = 0.5
    /// 学習に使うタップの、デコーダーの確信度の下限
    var minPosterior: Double = 0.85
    /// この回数だけ後の入力まで削除されなければ「正しかった」とみなして学習に使う
    var confirmAfter: Int = 3
    /// ヒートマップに残す、指×キーごとのタップの数
    var heatmapLimit: Int = 200
}

/// 個人適応: 利用者ごとの「押しがちなずれ」を、端末の中だけで学習する(7-2)。
///
/// ## 何を学ぶか
/// 指 f でキー k を狙ったときの、キーの中心からのずれ d(キーの大きさを 1 とした単位)。
/// これを空間タッチモデルの平均とばらつきに反映すると、例えば「G を狙うといつも少し左を押す人」に合わせて、
/// G の確率の山が左にずれます(Gboard の空間モデルの個人化、SwiftKey の Tap Map の考え方)。
///
/// ## どのタップを学習に使うか
/// - デコーダーの確信度が高く(minPosterior 以上)、その後 confirmAfter 回入力しても削除されなかったタップ
/// - 削除して打ち直した箇所: 消したタップの位置は「打ち直したキー」を狙っていた、とみなす
///
/// ## 縮小推定(データが少ないうちの暴走を防ぐ)
/// ```
///   指全体の平均   m_f = Σd(その指の全キー) / (κ + n_f)          … ずれ 0 に引き寄せる
///   キーの平均     μ   = (κ × m_f + Σd(そのキー)) / (κ + n)       … 指全体の平均に引き寄せる
/// ```
/// κ(priorStrength)回分のデータが集まるまでは、初期値の影響が大きく残ります。
/// これは Gunawardana ら(IUI 2010)のタッチモデルの学習(共役事前分布による MAP 推定)と同じ考え方です。
final class PersonalAdaptation: Codable {
    /// (指, キー) ごとのずれの統計
    struct Stats: Codable, Equatable {
        var n: Double = 0
        var sum = Vec2.zero
        var sumXX: Double = 0
        var sumXY: Double = 0
        var sumYY: Double = 0
        /// ヒートマップ用の、最近のずれ
        var recent: [Vec2] = []
    }

    /// 学習待ちのタップ
    struct PendingTap: Codable, Equatable {
        var finger: FingerID
        var keyID: String
        /// キーの中心からのずれ(キーの大きさ単位)
        var offset: Vec2
        /// 位置そのもの(打ち直したとき、別のキーからのずれを計算し直すため)
        var location: Vec2
        var posterior: Double
        var deleted = false
    }

    var config = AdaptationConfig()
    private(set) var stats: [String: Stats] = [:] {
        didSet { version += 1 }
    }
    /// 学習データが変わるたびに増える番号(変わったときだけモデルに反映し直すため)
    private(set) var version = 0
    private var pending: [PendingTap] = []
    /// 削除されたタップ(次に打ったキーが、本当に狙ったキー)
    private var deletedTaps: [PendingTap] = []

    init() {}

    static func key(finger: FingerID, keyID: String) -> String { "\(finger.id)|\(keyID)" }

    /// 記録したタップの総数
    var totalSamples: Int { Int(stats.values.reduce(0) { $0 + $1.n }) }

    func reset() {
        stats = [:]
        pending = []
        deletedTaps = []
    }

    // MARK: - 入力の記録

    /// タップでキーが入力された
    func recordTap(finger: FingerID, key: Key, location: Vec2, posterior: Double) {
        // 直前に削除されたタップがあれば、それは「このキーを狙っていた」とみなして学習する(打ち直し)
        if let deleted = deletedTaps.popLast() {
            if deleted.finger.chirality == finger.chirality {
                add(finger: deleted.finger, keyID: key.id, offset: Self.offset(of: deleted.location, from: key))
            }
            deletedTaps.removeAll()
        }
        pending.append(PendingTap(finger: finger, keyID: key.id, offset: Self.offset(of: location, from: key),
                                  location: location, posterior: posterior))
        // 十分前のタップは「正しかった」とみなして学習する
        while pending.count > config.confirmAfter {
            let confirmed = pending.removeFirst()
            if !confirmed.deleted, confirmed.posterior >= config.minPosterior {
                add(finger: confirmed.finger, keyID: confirmed.keyID, offset: confirmed.offset)
            }
        }
    }

    /// 削除ボタンが押された(最後のタップは間違いだった)
    func noteBackspace() {
        guard var last = pending.popLast() else { return }
        last.deleted = true
        deletedTaps.append(last)
    }

    /// キーのずれ(キーの大きさ単位)
    static func offset(of location: Vec2, from key: Key) -> Vec2 {
        let d = location - key.center
        return Vec2(d.x / max(key.size.x, 1e-9), d.y / max(key.size.y, 1e-9))
    }

    private func add(finger: FingerID, keyID: String, offset: Vec2) {
        var s = stats[Self.key(finger: finger, keyID: keyID)] ?? Stats()
        s.n += 1
        s.sum += offset
        s.sumXX += offset.x * offset.x
        s.sumXY += offset.x * offset.y
        s.sumYY += offset.y * offset.y
        s.recent.append(offset)
        if s.recent.count > config.heatmapLimit { s.recent.removeFirst(s.recent.count - config.heatmapLimit) }
        stats[Self.key(finger: finger, keyID: keyID)] = s
    }

    // MARK: - 推定

    /// 指全体の平均のずれ(ずれ 0 に引き寄せたもの)
    func fingerMeanOffset(_ finger: FingerID) -> Vec2 {
        let prefix = "\(finger.id)|"
        var n = 0.0, sum = Vec2.zero
        for (k, s) in stats where k.hasPrefix(prefix) {
            n += s.n
            sum += s.sum
        }
        return sum / (config.priorStrength + n)
    }

    /// (指, キー) の分布(キーの大きさ単位)。データが無ければ nil(初期値のまま)
    /// - Parameter priorSigma: 初期のばらつき(キーの大きさ単位の標準偏差)
    func estimate(finger: FingerID, keyID: String, priorSigma: Double) -> (offset: Vec2, covariance: Covariance2, n: Double)? {
        let fingerMean = fingerMeanOffset(finger)
        let s = stats[Self.key(finger: finger, keyID: keyID)] ?? Stats()
        guard s.n > 0 || fingerMean.length > 1e-9 else { return nil }
        let kappa = config.priorStrength
        var mean = (fingerMean * kappa + s.sum) / (kappa + s.n)
        // ずれの上限
        if mean.length > config.maxOffset { mean = mean * (config.maxOffset / mean.length) }
        // ばらつき: 初期値(κ 回分)と、データの散らばり(平均のまわり)を合わせる
        let p2 = priorSigma * priorSigma
        let sxx = s.sumXX - 2 * mean.x * s.sum.x + s.n * mean.x * mean.x
        let sxy = s.sumXY - mean.x * s.sum.y - mean.y * s.sum.x + s.n * mean.x * mean.y
        let syy = s.sumYY - 2 * mean.y * s.sum.y + s.n * mean.y * mean.y
        let covariance = Covariance2(xx: (kappa * p2 + sxx) / (kappa + s.n),
                                     xy: sxy / (kappa + s.n),
                                     yy: (kappa * p2 + syy) / (kappa + s.n))
        return (mean, covariance, s.n)
    }

    /// 空間タッチモデルに入れる分布(キー配置の座標の単位に直したもの)
    func learnedGaussians(keys: [Key], priorSigma: Double) -> [String: KeyGaussian] {
        var result: [String: KeyGaussian] = [:]
        for key in keys {
            let fingers: [FingerID] = key.isSpace
                ? Chirality.allCases.map { FingerID(chirality: $0, finger: .thumb) }
                : [FingerID(chirality: key.hand, finger: key.finger)]
            for finger in fingers where finger.chirality == key.hand {
                guard let e = estimate(finger: finger, keyID: key.id, priorSigma: priorSigma) else { continue }
                let sx = key.size.x, sy = key.size.y
                let gaussian = KeyGaussian(offset: Vec2(e.offset.x * sx, e.offset.y * sy),
                                           covariance: Covariance2(xx: e.covariance.xx * sx * sx,
                                                                   xy: e.covariance.xy * sx * sy,
                                                                   yy: e.covariance.yy * sy * sy),
                                           count: e.n)
                result[SpatialTouchModel.storageKey(finger: finger, key: key)] = gaussian
            }
        }
        return result
    }

    /// ヒートマップ用: キーごとの最近のタップ位置(キー配置の座標)
    func heatmapPoints(keys: [Key]) -> [(key: Key, points: [Vec2])] {
        keys.compactMap { key in
            let entries = stats.filter { $0.key.hasSuffix("|\(key.id)") }.flatMap { $0.value.recent }
            guard !entries.isEmpty else { return nil }
            return (key, entries.map { key.center + Vec2($0.x * key.size.x, $0.y * key.size.y) })
        }
    }

    // Codable(保存用): 学習待ちのタップは保存しない
    enum CodingKeys: String, CodingKey { case config, stats }

    /// 保存データを読み込む
    static func load(from data: Data) -> PersonalAdaptation? {
        try? JSONDecoder().decode(PersonalAdaptation.self, from: data)
    }
}
