"""Swift とのゴールデンテスト用の正解データを作る。

使い方(リポジトリのルートで):
    python3 tools/lm/make_golden.py
出力: Tests/ARKeyboardCoreTests/Fixtures/lm_golden.json
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from ngram import CharNGramModel  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
CORPUS = os.path.join(ROOT, "ARKeyboard", "Resources", "Corpus")

CONTEXTS = ["", "t", "th", "the", "the q", "hello wor", "i am typ", "konnichi", "arigatou ", "xyz", "zzzz zzzz", "kyou ha "]
CHARS = list("aehnoqrstuyz ,.;")


def main() -> None:
    cases = []
    for name in ["english", "romaji"]:
        with open(os.path.join(CORPUS, f"corpus_{name}.txt"), encoding="utf-8") as f:
            text = f.read()
        for order in [1, 3, 5]:
            model = CharNGramModel(text, order)
            for ctx in CONTEXTS:
                for c in CHARS:
                    cases.append({"corpus": name, "order": order, "context": ctx, "char": c,
                                  "p": model.probability(c, ctx)})
    out = os.path.join(ROOT, "Tests", "ARKeyboardCoreTests", "Fixtures", "lm_golden.json")
    with open(out, "w", encoding="utf-8") as f:
        json.dump(cases, f, ensure_ascii=False, indent=0)
    print(f"wrote {len(cases)} cases to {out}")


if __name__ == "__main__":
    main()
