import Foundation

/// 単語の辞書(学習用テキストに出てきた単語と、その「頭の部分(接頭辞)」)
struct Lexicon {
    private(set) var words: Set<String> = []
    private(set) var prefixes: Set<String> = []

    init(text: String) {
        let normalized = CharNGramModel.normalize(text)
        for raw in normalized.split(whereSeparator: { " ,.;".contains($0) }) {
            add(String(raw))
        }
    }

    mutating func add(_ word: String) {
        guard !word.isEmpty else { return }
        words.insert(word)
        var prefix = ""
        for c in word {
            prefix.append(c)
            prefixes.insert(prefix)
        }
    }

    func isPrefix(_ s: String) -> Bool { prefixes.contains(s) }
    func isWord(_ s: String) -> Bool { words.contains(s) }
}

/// 単語単位のデコード(VelociTap の文単位のデコードを、単語単位に縮小したもの)。
///
/// 1文字ずつ「その時点でいちばん確からしいキー」を決めると、前の文字の誤りを後から直せません。
/// そこで、今打っている単語のタップごとに候補(上位いくつか)を残しておき、
/// 単語全体として最もらしい綴りを「ビームサーチ」で探します。
///
/// ```
///   単語のスコア = Σ [ log p(位置 | キー) + w × log P(文字 | 直前の文字) ] − 辞書に無い綴りの罰点
/// ```
/// ビームサーチ: 候補の組み合わせは「候補数^文字数」通りあって全部は調べられないので、
/// 1文字進むごとにスコアの高い上位 beamWidth 個だけを残して先へ進みます。
final class WordBeamDecoder {
    struct Config: Codable, Equatable {
        /// 残す候補の数
        var beamWidth: Int = 8
        /// 1タップあたり、何個の候補キーを考えるか
        var candidatesPerTap: Int = 4
        /// 辞書のどの単語の頭にもならない綴りに付ける罰点(対数)
        var lexiconPenalty: Double = 2.5
    }

    var config = Config()
    /// 言語モデル(nil なら使わない)
    var languageModel: ((Character, String) -> Double)?
    var lmWeight: Double = 0.4
    var lexicon: Lexicon?

    init() {}

    /// 単語の各タップの候補から、最もらしい綴りを返す
    /// - Parameters:
    ///   - steps: タップごとの候補(KeyCandidate の logSpatial を使う)
    ///   - context: 単語の直前までの文字列(言語モデルの文脈)
    func decode(steps: [[KeyCandidate]], context: String) -> String {
        decodeNBest(steps: steps, context: context).first?.text ?? ""
    }

    /// 上位の候補(スコアの高い順)
    func decodeNBest(steps: [[KeyCandidate]], context: String) -> [(text: String, score: Double)] {
        var beams: [(text: String, score: Double)] = [("", 0)]
        for step in steps {
            let options = step.sorted { $0.probability > $1.probability }.prefix(config.candidatesPerTap)
            var next: [(text: String, score: Double)] = []
            for beam in beams {
                for option in options {
                    guard let c = option.key.output.first else { continue }
                    let text = beam.text + String(c)
                    var score = beam.score + option.logSpatial
                    if let lm = languageModel, lmWeight > 0 {
                        score += lmWeight * log(max(lm(c, context + beam.text), 1e-300))
                    }
                    if let lexicon, !lexicon.isPrefix(text) {
                        score -= config.lexiconPenalty
                    }
                    next.append((text, score))
                }
            }
            // 同じ綴りが複数の道筋でできたら、スコアの高い方だけ残す
            var best: [String: Double] = [:]
            for n in next where n.score > (best[n.text] ?? -Double.infinity) {
                best[n.text] = n.score
            }
            var merged: [(text: String, score: Double)] = []
            for (text, score) in best {
                merged.append((text: text, score: score))
            }
            // スコアが同じときは綴りの順で並べる(辞書の並び順は毎回変わるので、結果がぶれないように)
            merged.sort { a, b in
                if a.score != b.score { return a.score > b.score }
                return a.text < b.text
            }
            beams = Array(merged.prefix(config.beamWidth))
        }
        return beams
    }
}
