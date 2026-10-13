"""ローマ字(ヘボン式に近い書き方)をひらがなに変換する。

仮名の言語モデル(フリック入力用)の学習データを、自作のローマ字コーパス
(ARKeyboard/Resources/Corpus/corpus_romaji.txt)から作るために使う。

    python3 tools/lm/romaji_to_kana.py > ARKeyboard/Resources/Corpus/corpus_kana.txt

- 単語の間のスペースは消す(日本語は分かち書きしない)
- "," → "、"、"." → "。"
- 子音の重なり(kk, tt など)→ 「っ」、n の後ろが母音や y でなければ「ん」
- 外来語の長音はローマ字どおり(例: "deeta" → でえた)になる。学習データとしてはやや不自然。
"""
import os
import sys

TABLE = {
    "kya": "きゃ", "kyu": "きゅ", "kyo": "きょ", "sha": "しゃ", "shu": "しゅ", "sho": "しょ", "shi": "し",
    "cha": "ちゃ", "chu": "ちゅ", "cho": "ちょ", "chi": "ち", "tsu": "つ", "nya": "にゃ", "nyu": "にゅ",
    "nyo": "にょ", "hya": "ひゃ", "hyu": "ひゅ", "hyo": "ひょ", "mya": "みゃ", "myu": "みゅ", "myo": "みょ",
    "rya": "りゃ", "ryu": "りゅ", "ryo": "りょ", "gya": "ぎゃ", "gyu": "ぎゅ", "gyo": "ぎょ", "ja": "じゃ",
    "ju": "じゅ", "jo": "じょ", "ji": "じ", "bya": "びゃ", "byu": "びゅ", "byo": "びょ", "pya": "ぴゃ",
    "pyu": "ぴゅ", "pyo": "ぴょ", "fu": "ふ",
    "ka": "か", "ki": "き", "ku": "く", "ke": "け", "ko": "こ", "sa": "さ", "su": "す", "se": "せ", "so": "そ",
    "ta": "た", "te": "て", "to": "と", "na": "な", "ni": "に", "nu": "ぬ", "ne": "ね", "no": "の",
    "ha": "は", "hi": "ひ", "he": "へ", "ho": "ほ", "ma": "ま", "mi": "み", "mu": "む", "me": "め", "mo": "も",
    "ya": "や", "yu": "ゆ", "yo": "よ", "ra": "ら", "ri": "り", "ru": "る", "re": "れ", "ro": "ろ",
    "wa": "わ", "wo": "を", "ga": "が", "gi": "ぎ", "gu": "ぐ", "ge": "げ", "go": "ご", "za": "ざ", "zu": "ず",
    "ze": "ぜ", "zo": "ぞ", "da": "だ", "de": "で", "do": "ど", "ba": "ば", "bi": "び", "bu": "ぶ", "be": "べ",
    "bo": "ぼ", "pa": "ぱ", "pi": "ぴ", "pu": "ぷ", "pe": "ぺ", "po": "ぽ",
    "a": "あ", "i": "い", "u": "う", "e": "え", "o": "お",
}
VOWELS = set("aiueo")


def convert_word(word: str) -> str:
    out = []
    i = 0
    while i < len(word):
        c = word[i]
        # 促音: 同じ子音が続く(n 以外)
        if i + 1 < len(word) and c == word[i + 1] and c not in VOWELS and c != "n":
            out.append("っ")
            i += 1
            continue
        if c == "t" and word[i:i + 3] == "tch":
            out.append("っ")
            i += 1
            continue
        # ん: n の後ろが母音でも y でもない(または単語の終わり)
        if c == "n" and (i + 1 == len(word) or (word[i + 1] not in VOWELS and word[i + 1] != "y")):
            out.append("ん")
            i += 1
            continue
        for length in (3, 2, 1):
            chunk = word[i:i + length]
            if chunk in TABLE:
                out.append(TABLE[chunk])
                i += length
                break
        else:
            i += 1  # 変換できない文字は捨てる
    return "".join(out)


def convert(text: str) -> str:
    lines = []
    for line in text.lower().splitlines():
        line = line.replace(",", " 、 ").replace(".", " 。 ")
        parts = []
        for token in line.split():
            parts.append(token if token in ("、", "。") else convert_word(token))
        lines.append("".join(parts))
    return "\n".join(lines) + "\n"


if __name__ == "__main__":
    root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
    src = sys.argv[1] if len(sys.argv) > 1 else os.path.join(root, "ARKeyboard", "Resources", "Corpus", "corpus_romaji.txt")
    with open(src, encoding="utf-8") as f:
        sys.stdout.write(convert(f.read()))
