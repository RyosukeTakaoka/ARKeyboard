import Foundation

/// 文字 n-gram 言語モデル(「直前の数文字から、次の文字の確率」を出す)。
///
/// ## 何に使うか
/// 指先の位置だけでは F と G のどちらを押したか迷うとき、直前の文字から
/// 「次に来やすい文字」を確率で出して補います(Goodman らのソフトキーボードの研究と同じ考え方)。
///
/// ## 計算方法: Witten-Bell の補間(なめらかにする工夫)
/// 学習データに一度も出てこなかった並びの確率を 0 にしてしまうと、そのキーが絶対に打てなくなります。
/// そこで「長い文脈での推定」と「1文字短い文脈での推定」を混ぜます:
/// ```
///   P(c | h) = ( C(h,c) + T(h) × P(c | hの先頭を1文字削ったもの) ) / ( C(h) + T(h) )
/// ```
/// - C(h,c): 文脈 h の後に文字 c が来た回数
/// - C(h):   文脈 h の後に何かの文字が来た回数の合計
/// - T(h):   文脈 h の後に来た「文字の種類の数」(いろいろな文字が来る文脈ほど、短い文脈に頼る)
/// - 文脈の長さ 0(最後の段)は、すべての文字に 1 回ずつ足した「加算スムージング」の頻度。
///
/// Python 版(tools/lm/ngram.py)も同じ式で、両者の出力が一致することをテストで確認しています。
struct CharNGramModel {
    /// このキーボード(QWERTY)で打てる文字(30種類)。これ以外の文字は学習時に取り除く。
    static let vocabulary: [Character] = Array("abcdefghijklmnopqrstuvwxyz ,.;")

    /// n-gram の n(文脈は n−1 文字)
    let order: Int
    /// このモデルが扱う文字(英字用・仮名用で違う)
    let symbols: [Character]
    private let allowed: Set<Character>
    /// 文脈 → (次の文字 → 回数)
    private var counts: [String: [Character: Int]] = [:]
    /// 文脈 → 合計回数
    private var totals: [String: Int] = [:]

    /// 学習用のテキストから作る
    /// - Parameter vocabulary: 扱う文字(既定は英字)。仮名のモデルなら FlickLayout.kanaVocabulary
    init(text: String, order: Int = 5, vocabulary: [Character] = CharNGramModel.vocabulary) {
        self.order = max(1, order)
        self.symbols = vocabulary
        self.allowed = Set(vocabulary)
        let normalized = Self.normalize(text, allowed: allowed)
        let chars = Array(normalized)
        for i in 0..<chars.count {
            let c = chars[i]
            // 文脈の長さ 0〜order-1 のすべてで数える
            for n in 0..<self.order {
                guard i - n >= 0 else { break }
                let context = String(chars[(i - n)..<i])
                counts[context, default: [:]][c, default: 0] += 1
                totals[context, default: 0] += 1
            }
        }
    }

    /// 学習・推定の前に文字をそろえる: 小文字にし、改行やタブはスペースに、打てない文字は消し、
    /// スペースの連続は1つにまとめる。
    static func normalize(_ text: String, allowed: Set<Character> = Set(vocabulary)) -> String {
        var result = ""
        var lastWasSpace = false
        for ch in text.lowercased() {
            let c: Character = (ch == "\n" || ch == "\t" || ch == "\r") ? " " : ch
            guard allowed.contains(c) else { continue }
            if c == " " {
                if lastWasSpace { continue }
                lastWasSpace = true
            } else {
                lastWasSpace = false
            }
            result.append(c)
        }
        return result
    }

    /// P(c | context)。context は直前の文字列(長くてもよい。最後の order−1 文字だけ使う)。
    func probability(of c: Character, after context: String) -> Double {
        let normalizedContext = Array(Self.normalize(context, allowed: allowed))
        let historyLength = min(order - 1, normalizedContext.count)
        let history = String(normalizedContext.suffix(historyLength))
        return interpolated(c, history: history)
    }

    /// log P(c | context)
    func logProbability(of c: Character, after context: String) -> Double {
        log(max(probability(of: c, after: context), 1e-300))
    }

    private func interpolated(_ c: Character, history: String) -> Double {
        if history.isEmpty {
            // 文脈なし: 加算スムージング(すべての文字に1回ずつ足す)
            let count = Double(counts[""]?[c] ?? 0)
            let total = Double(totals[""] ?? 0)
            return (count + 1) / (total + Double(symbols.count))
        }
        let shorter = interpolated(c, history: String(history.dropFirst()))
        guard let total = totals[history], total > 0, let next = counts[history] else {
            return shorter
        }
        let types = Double(next.count)
        let count = Double(next[c] ?? 0)
        return (count + types * shorter) / (Double(total) + types)
    }
}

/// 2つの言語モデルを混ぜる(英語とローマ字の両方を使うとき)
struct MixedLanguageModel {
    var models: [(model: CharNGramModel, weight: Double)]

    func probability(of c: Character, after context: String) -> Double {
        let totalWeight = models.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return 1 / Double(CharNGramModel.vocabulary.count) }
        return models.reduce(0) { $0 + $1.weight * $1.model.probability(of: c, after: context) } / totalWeight
    }
}
