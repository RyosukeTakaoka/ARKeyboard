"""評価ツール・アルゴリズムの Python 版と Swift 版を比べるための正解データを作る。

    python3 tools/eval/make_golden.py
出力: Tests/ARKeyboardCoreTests/Fixtures/onset_golden.json
"""
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from onset import OnsetDetector  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


def main() -> None:
    # 決まった式で作る入力(乱数を使わず、Swift でも同じ値を作れるようにする)
    values = []
    for i in range(600):
        t = i * 0.0106667
        v = 0.002 + 0.001 * (0.5 + 0.5 * math.sin(i * 1.7) * math.cos(i * 0.31))
        if i % 97 == 50:
            v += 0.05
        if i % 131 == 7:
            v += 0.02
        values.append((t, v))
    det = OnsetDetector()
    onsets, thresholds = [], []
    for t, v in values:
        e = det.process(v, t)
        thresholds.append(det.last_threshold)
        if e:
            onsets.append(e)
    out = os.path.join(ROOT, "Tests", "ARKeyboardCoreTests", "Fixtures", "onset_golden.json")
    with open(out, "w", encoding="utf-8") as f:
        json.dump({"inputs": values, "onsets": onsets, "thresholds": thresholds}, f)
    print(f"wrote {len(onsets)} onsets to {out}")


if __name__ == "__main__":
    main()
