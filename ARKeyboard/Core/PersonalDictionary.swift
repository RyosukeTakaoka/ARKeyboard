import Foundation

/// 個人辞書(7-2・Tier3)。利用者が確定した文字列を端末内に覚えておき、言語モデルと単語の辞書に足す。
///
/// ## 何を覚えるか
/// 空白・改行・句読点で区切られた「確定した単語(フレーズ)」を、区切りごとに追記します。
/// 単語だけでなく区切りを含めた並びをそのまま覚えるので、よく打つ言い回し(例: "see you tomorrow")も
/// 文字 n-gram で自然に覚えます(Samsung の「個人のフレーズ」を簡単にした形。7-0 の調査は未確認の資料)。
/// - 英字・ローマ字(QWERTY)と仮名(フリック)は別々に覚える
/// - 古いものから捨てて、それぞれ最大 maxCharacters 文字まで(端末の容量と、昔の癖を引きずらないため)
/// - 保存先はアプリの Application Support フォルダ(端末の外には送らない)。設定画面から消せる
///
/// ## どう使うか(PersonalLanguageModel)
/// 覚えた文字列で小さな文字 n-gram を作り、元の言語モデルと混ぜます:
/// ```
///   P(c | h) = (1 − λ(h)) × P_元(c | h) + λ(h) × P_個人(c | h)
///   λ(h) = weight × n(h) / (n(h) + 3)      n(h): 個人の文字列で、直前の文脈 h が出てきた回数
/// ```
/// 個人のデータは少ないので、見たことのない文脈では λ を小さくして、元のモデルを薄めないようにしています。
struct PersonalDictionary: Codable, Equatable {
    /// 英字・ローマ字(QWERTY)の確定文字列
    var text: String = ""
    /// 仮名(フリック)の確定文字列
    var kanaText: String = ""
    /// 変わるたびに増える(言語モデルを作り直すかどうかの判断に使う)
    var version: Int = 0

    static let maxCharacters = 5000
    /// 区切り(これが打たれたら、直前の単語を確定とみなす)
    static let delimiters: Set<Character> = [" ", "\n", ".", ",", "、", "。", "?", "!"]

    var isEmpty: Bool { text.isEmpty && kanaText.isEmpty }

    /// 覚えている単語の数(画面表示用)
    var wordCount: Int {
        (text + " " + kanaText).split(whereSeparator: { Self.delimiters.contains($0) }).count
    }

    /// 画面の文字列が old から new に変わったとき、区切りが打たれていれば直前の単語を覚える
    /// - Returns: 覚えたら true
    @discardableResult
    mutating func learn(old: String, new: String) -> Bool {
        // 末尾に1文字(区切り)が追加されたときだけ
        guard new.count == old.count + 1, new.hasPrefix(old), let last = new.last, Self.delimiters.contains(last) else {
            return false
        }
        // 直前の区切りから、今の区切りまで
        let body = old.reversed().prefix { !Self.delimiters.contains($0) }
        let word = String(body.reversed())
        guard word.count >= 2 else { return false }
        let isKana = word.unicodeScalars.allSatisfy { (0x3040...0x30FF).contains($0.value) }
        if isKana {
            kanaText = Self.trimmed(kanaText + word + String(last))
        } else {
            let normalized = CharNGramModel.normalize(word)
            guard normalized.count >= 2 else { return false }
            // 区切りは英字の言語モデルで使える文字にそろえる(改行 → 空白)
            let delimiter = CharNGramModel.normalize(String(last)).isEmpty ? " " : CharNGramModel.normalize(String(last))
            text = Self.trimmed(text + normalized + delimiter)
        }
        version += 1
        return true
    }

    mutating func reset() {
        text = ""
        kanaText = ""
        version += 1
    }

    private static func trimmed(_ s: String) -> String {
        s.count > maxCharacters ? String(s.suffix(maxCharacters)) : s
    }
}

/// 個人辞書の設定
struct PersonalDictionaryConfig: Codable, Equatable {
    /// 個人の言語モデルの重みの上限(λ の最大)
    var weight: Double = 0.3
}

/// 元の言語モデルに、個人の文字列から作った言語モデルを混ぜる
struct PersonalLanguageModel {
    let base: (Character, String) -> Double
    let personal: CharNGramModel
    let weight: Double

    func probability(of c: Character, after context: String) -> Double {
        let n = Double(personal.contextCount(context))
        let lambda = weight * n / (n + 3)
        return (1 - lambda) * base(c, context) + lambda * personal.probability(of: c, after: context)
    }
}
