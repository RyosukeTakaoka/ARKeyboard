"""評価指標の計算(記録の目標 vs 再生結果)。

用語:
- 目標(プロンプト): 画面に出した「打ってほしい文字」。i 番目の目標は、表示された時刻から次の目標の表示までの
  「時間窓」に打たれたはず、とみなす。
- 採用されたタップ: 文字が入力されたタップ(却下・範囲外は除く)。

指標:
- タップ検出の適合率(precision): 採用されたタップのうち、本物(各窓の最初の1つ)だった割合
- タップ検出の再現率(recall): 目標のうち、窓の中で少なくとも1回は採用されたタップがあった割合
- キー正解率: 本物のタップのうち、入力された文字が目標と一致した割合
- 文字誤り率(CER): 入力された文字列と目標の文字列の編集距離 ÷ 目標の長さ
- 推定WPM: 入力された文字数 ÷ 5 ÷ 最初から最後のタップまでの分
- 指ごとの誤り: キーを間違えた本物のタップを、目標の文字の担当の指ごとに数える
"""
from __future__ import annotations

from collections import Counter

# キーボードの配置と担当の指(ARKeyboard/Core/KeyLayout.swift と同じ)
LEFT_ROWS = ["qwert", "asdfg", "zxcvb"]
RIGHT_ROWS = ["yuiop", "hjkl;", "nm,."]
LEFT_FINGERS = ["little", "ring", "middle", "index", "index"]
RIGHT_FINGERS = ["index", "index", "middle", "ring", "little"]


def finger_for(char: str) -> str:
    if char == " ":
        return "thumb"
    for row in LEFT_ROWS:
        if char in row:
            return "left-" + LEFT_FINGERS[row.index(char)]
    for row in RIGHT_ROWS:
        if char in row:
            return "right-" + RIGHT_FINGERS[row.index(char)]
    return "?"


def edit_distance(a: str, b: str) -> int:
    """レーベンシュタイン距離(挿入・削除・置換の最小回数)"""
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i]
        for j, cb in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca != cb)))
        prev = cur
    return prev[-1]


def evaluate(prompts: list[dict], taps: list[dict]) -> dict:
    """1つの記録 × 1つのバリアントの指標を計算する"""
    accepted = sorted((t for t in taps if t.get("accepted") and t.get("output") is not None), key=lambda t: t["t"])
    windows = []
    for i, p in enumerate(prompts):
        start = p["shownAt"]
        end = prompts[i + 1]["shownAt"] if i + 1 < len(prompts) else start + 2.0
        windows.append((start, end, p["target"]))

    tp = fp = fn = correct = 0
    finger_errors: Counter = Counter()
    used = set()
    for start, end, target in windows:
        inside = [k for k, t in enumerate(accepted) if start <= t["t"] < end]
        if not inside:
            fn += 1
            continue
        tp += 1
        first = accepted[inside[0]]
        used.update(inside)
        fp += len(inside) - 1
        if first["output"] == target:
            correct += 1
        else:
            finger_errors[finger_for(target)] += 1
    fp += len([k for k in range(len(accepted)) if k not in used])

    hyp = "".join(t["output"] for t in accepted)
    ref = "".join(p["target"] for p in prompts)
    duration = (accepted[-1]["t"] - accepted[0]["t"]) if len(accepted) >= 2 else 0
    return {
        "precision": tp / (tp + fp) if tp + fp else 0.0,
        "recall": tp / (tp + fn) if tp + fn else 0.0,
        "key_accuracy": correct / tp if tp else 0.0,
        "cer": edit_distance(hyp, ref) / max(len(ref), 1),
        "wpm": (len(hyp) / 5) / (duration / 60) if duration > 0 else 0.0,
        "finger_errors": dict(finger_errors),
        "hypothesis": hyp,
        "reference": ref,
        "taps": len(taps),
        "accepted": len(accepted),
    }
