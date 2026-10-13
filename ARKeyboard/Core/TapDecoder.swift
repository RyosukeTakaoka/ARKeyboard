import Foundation

/// デコーダーが使う言語
enum DecoderLanguage: String, Codable, CaseIterable, Identifiable {
    case english
    case romaji
    /// 英語とローマ字を半分ずつ混ぜる
    case mixed

    var id: String { rawValue }

    var japaneseName: String {
        switch self {
        case .english: return "英語"
        case .romaji: return "ローマ字(日本語)"
        case .mixed: return "英語+ローマ字"
        }
    }
}

/// デコーダーの設定(すべて設定画面で変えられ、評価ツールで最適化できる)
struct DecoderConfig: Codable, Equatable {
    var language: DecoderLanguage = .english
    /// n-gram の n
    var lmOrder: Int = 5
    /// 言語モデルの重み w(事後確率 ∝ 位置の尤度 × 言語の確率^w)。
    /// 0 なら言語モデルを使わないのと同じ。大きいほど文脈を重視する。
    /// 初期値 0.4 は、合成データ(学習データに無い英文)で w = 0〜1.5 を比べた結果から仮に決めた値
    /// (docs/results.md)。実際の記録データで調整し直すこと。
    var lmWeight: Double = 0.4
    /// キーごとの分布の、初期のばらつき(キーの大きさに対する割合)
    var keySigma: Double = 0.3
    /// 測定(カメラ)の不確かさ(キー間隔に対する割合)
    var measurementSigma: Double = 0.2
    /// アンカー: キーの中央の、この割合の範囲は、文脈に関係なく必ずそのキーにする(0 で無効)。
    /// Gunawardana ら(IUI 2010)の「見えているキーの真ん中を押せば必ずそのキー」を守るための工夫。
    var anchorFraction: Double = 0.3
    /// 「指の担当キーだけ」にしないとき、担当外のキーに付ける罰点(対数)。大きいほど担当キーを優先
    var offFingerPenalty: Double = 3.0
    /// 入力速度への適応を使うか
    var speedAdaptation: Bool = true
    /// 前のタップからの間隔がこれ以下なら「速い」(秒)
    var fastInterval: Double = 0.18
    /// 間隔がこれ以上なら「ゆっくり」(秒)。間は直線で補間する
    var slowInterval: Double = 0.6
    /// 速いとき、位置のばらつきを (1 + この値) 倍に見積もる
    var fastSigmaGain: Double = 0.5
    /// 速いとき、言語モデルの重みを (1 + この値) 倍にする
    var fastLMGain: Double = 0.5
}

/// キーの候補と、その事後確率
struct KeyCandidate: Equatable {
    var key: Key
    /// 事後確率(候補全体で合計 1)
    var probability: Double
    /// log p(位置 | キー)
    var logSpatial: Double
    /// log p(キー | 文脈)(言語モデルを使わないときは 0)
    var logLanguage: Double
}

/// デコードの結果
struct DecodeResult: Equatable {
    /// 事後確率の高い順
    var candidates: [KeyCandidate]
    /// 選ばれたキー
    var best: Key?
    /// アンカーの中だったので、文脈に関係なく決まったか
    var anchored: Bool
    /// 入力の速さ(0 = ゆっくり 〜 1 = 速い)
    var speed: Double
}

/// 1回のタップを「キーごとの確率」にして、いちばん確からしいキーを選ぶ(Tier1 のデコーダー)。
///
/// ## 式(Goodman ら 2002、Gunawardana ら 2010 の source-channel の形)
/// ```
///   P(キー k | 位置 x, 指 f, 文脈 h) ∝ p(x | k, f) × P(k | f) × P(k | h)^w
/// ```
/// - p(x | k, f): 空間タッチモデル(指×キーごとの2変量ガウス分布)
/// - P(k | f): 指の制約(左手の人差し指なら R T F G V B だけ、など)
/// - P(k | h): 文字 n-gram 言語モデル(直前の文字から次の文字の確率)
/// - w: 言語モデルの重み(位置と言語の「強さ」の釣り合い)
///
/// 入力が速い(前のタップとの間隔が短い)ほど、位置のばらつきを大きく見積もり、言語モデルの重みを上げます
/// (速く打つと狙いが雑になる、という仮説。パラメータは記録データで調整する)。
final class TapDecoder {
    var config = DecoderConfig()
    let spatial = SpatialTouchModel()
    /// 言語モデル(nil なら使わない)
    var languageModel: ((Character, String) -> Double)?

    init() {}

    /// 前のタップとの間隔(秒)から、入力の速さ(0〜1)を求める
    func speed(forInterval interval: Double?) -> Double {
        guard config.speedAdaptation, let interval else { return 0 }
        let fast = config.fastInterval, slow = max(config.slowInterval, fast + 1e-3)
        return min(max((slow - interval) / (slow - fast), 0), 1)
    }

    /// その指で打ってよいキーか(親指はスペースだけ、他の指はスペース以外)
    static func isAllowed(_ key: Key, finger: Finger?) -> Bool {
        guard let finger else { return !key.isSpace }
        return (finger == .thumb) == key.isSpace
    }

    /// 1回のタップをデコードする
    /// - Parameters:
    ///   - location: タップ位置(キー配置の座標)
    ///   - measurementCovariance: 位置の測定の不確かさ
    ///   - finger: どの指か(nil なら指を問わない。当たり判定ビュー用)
    ///   - keys: その手のキー
    ///   - context: 直前に入力された文字列
    ///   - interval: 前のタップからの時間(秒)
    ///   - restrictToFinger: 指の担当キーだけから選ぶか
    ///   - useLanguageModel: 言語モデルを使うか
    func decode(location: Vec2,
                measurementCovariance: Covariance2,
                finger: FingerID?,
                keys: [Key],
                context: String,
                interval: Double?,
                restrictToFinger: Bool,
                useLanguageModel: Bool,
                languageCache: [Character: Double]? = nil) -> DecodeResult {
        spatial.priorSigmaFraction = config.keySigma
        let speed = self.speed(forInterval: interval)
        let sigmaScale = 1 + config.fastSigmaGain * speed
        let lmWeight = useLanguageModel && languageModel != nil ? config.lmWeight * (1 + config.fastLMGain * speed) : 0

        var scored: [(key: Key, logPosterior: Double, logSpatial: Double, logLanguage: Double)] = []
        for key in keys where Self.isAllowed(key, finger: finger?.finger) {
            // 指の制約
            var fingerPrior = 0.0
            if let finger, finger.finger != .thumb, key.finger != finger.finger {
                if restrictToFinger { continue }
                fingerPrior = -config.offFingerPenalty
            }
            let logSpatial = spatial.logLikelihood(of: location, key: key, finger: finger,
                                                   measurementCovariance: measurementCovariance,
                                                   sigmaScale: sigmaScale)
            var logLanguage = 0.0
            if lmWeight > 0, let lm = languageModel, let c = key.output.first {
                // 同じ文脈で何度も呼ぶとき(当たり判定の地図)は、計算済みの値を使う
                let p = languageCache?[c] ?? lm(c, context)
                logLanguage = log(max(p, 1e-300))
            }
            scored.append((key, logSpatial + fingerPrior + lmWeight * logLanguage, logSpatial, logLanguage))
        }
        guard !scored.isEmpty else { return DecodeResult(candidates: [], best: nil, anchored: false, speed: speed) }

        // 確率に直して合計を 1 にする(log-sum-exp: 大きな値を引いてから exp すると桁あふれしない)
        let maxLog = scored.map(\.logPosterior).max() ?? 0
        let sum = scored.reduce(0.0) { $0 + exp($1.logPosterior - maxLog) }
        let candidates = scored
            .map { KeyCandidate(key: $0.key, probability: exp($0.logPosterior - maxLog) / sum,
                                logSpatial: $0.logSpatial, logLanguage: $0.logLanguage) }
            .sorted { $0.probability > $1.probability }

        // アンカー: キーの中央付近なら、文脈に関係なくそのキー
        if let anchoredKey = anchorKey(at: location, among: candidates.map(\.key)) {
            return DecodeResult(candidates: candidates, best: anchoredKey, anchored: true, speed: speed)
        }
        return DecodeResult(candidates: candidates, best: candidates.first?.key, anchored: false, speed: speed)
    }

    /// 位置がどれかのキーのアンカー(中央の範囲)の中なら、そのキー
    func anchorKey(at location: Vec2, among keys: [Key]) -> Key? {
        guard config.anchorFraction > 0 else { return nil }
        return keys.first { key in
            let d = location - key.center
            return abs(d.x) <= key.size.x * config.anchorFraction / 2
                && abs(d.y) <= key.size.y * config.anchorFraction / 2
        }
    }

    /// 当たり判定の地図: 各格子点で「事後確率が最大のキー」を求める(7-3 当たり判定ビュー)。
    /// 文脈が変わると、言語モデルの事前確率が変わり、各キーの領域が広がったり縮んだりします。
    func hitMap(keys: [Key], context: String, useLanguageModel: Bool,
                columns: Int = 36, rows: Int = 24) -> HitMap? {
        let candidates = keys.filter { !$0.isSpace }
        guard let first = candidates.first else { return nil }
        // キー全体を囲む長方形(少し余白を取る)
        var minX = first.center.x, maxX = first.center.x, minY = first.center.y, maxY = first.center.y
        for key in candidates {
            minX = min(minX, key.center.x - key.size.x); maxX = max(maxX, key.center.x + key.size.x)
            minY = min(minY, key.center.y - key.size.y); maxY = max(maxY, key.center.y + key.size.y)
        }
        let cellSize = Vec2((maxX - minX) / Double(columns), (maxY - minY) / Double(rows))
        var cells: [HitMap.Cell] = []
        cells.reserveCapacity(columns * rows)
        let noMeasurement = Covariance2(xx: 0, xy: 0, yy: 0)
        // 言語モデルの値は、どの格子点でも同じなので先に1回だけ計算しておく
        var cache: [Character: Double] = [:]
        if let lm = languageModel {
            for key in candidates { if let c = key.output.first { cache[c] = lm(c, context) } }
        }
        for row in 0..<rows {
            for column in 0..<columns {
                let center = Vec2(minX + (Double(column) + 0.5) * cellSize.x, minY + (Double(row) + 0.5) * cellSize.y)
                let result = decode(location: center, measurementCovariance: noMeasurement, finger: nil,
                                    keys: candidates, context: context, interval: nil,
                                    restrictToFinger: false, useLanguageModel: useLanguageModel,
                                    languageCache: cache)
                guard let best = result.best else { continue }
                let probability = result.candidates.first { $0.key.id == best.id }?.probability ?? 0
                cells.append(HitMap.Cell(center: center, keyID: best.id, probability: probability))
            }
        }
        return HitMap(cells: cells, cellSize: cellSize)
    }
}

/// 当たり判定の地図(キー配置の座標の格子)
struct HitMap: Equatable {
    struct Cell: Equatable {
        /// 格子の中心(キー配置の座標)
        var center: Vec2
        /// ここを押したときに選ばれるキー
        var keyID: String
        /// そのキーの事後確率
        var probability: Double
    }

    var cells: [Cell]
    var cellSize: Vec2

    /// 各キーの領域の広さ(格子の数)。文脈で領域が広がる様子を数字でも見られるようにする
    var areaByKey: [String: Int] {
        cells.reduce(into: [:]) { $0[$1.keyID, default: 0] += 1 }
    }
}
