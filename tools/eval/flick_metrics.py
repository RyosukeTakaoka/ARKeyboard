"""フリック入力の評価指標(記録の目標 vs 再生結果)。

配置は ARKeyboard/Core/Kana.swift の FlickLayout と同じ(test_metrics.py で一部を確認)。

指標:
- 検出の再現率: 目標(1文字)のうち、その表示中に少なくとも1回フリックが検出された割合
- 検出の適合率: 検出されたフリックのうち、目標に対応づいた(各目標の最初の1回)割合
- 始点キー正解率: 対応づいたフリックのうち、始点のキー(あ・か…の行)が正しかった割合
- 方向正解率: 対応づいたフリックのうち、方向(タップ・左・上・右・下)が正しかった割合
- 仮名正解率: 対応づいたフリックのうち、そのフリック単独の解読(1位)が正しい仮名だった割合
  (濁点・小文字は機能パッドで付けるので、ここでは元の仮名で比べる)
- CER: 最終的な文字列(並びの解読・濁点の付与を反映)と目標の編集距離 ÷ 目標の長さ
- CPM: 1分あたりの入力文字数(最初から最後のフリックまで)
- 方向の混同行列: 正しい方向 × 解読された方向 の回数
"""
from __future__ import annotations

from metrics import edit_distance

DIRECTIONS = ["タップ", "左", "上", "右", "下"]

# 4段 × 3列。各キー: (表示名, [タップ, 左, 上, 右, 下])
FLICK_ROWS = [
    [("あ", list("あいうえお")), ("か", list("かきくけこ")), ("さ", list("さしすせそ"))],
    [("た", list("たちつてと")), ("な", list("なにぬねの")), ("は", list("はひふへほ"))],
    [("ま", list("まみむめも")), ("や", ["や", "「", "ゆ", "」", "よ"]), ("ら", list("らりるれろ"))],
    [("゛゜小", ["゛", None, None, None, None]), ("わ", ["わ", "を", "ん", "ー", None]),
     ("、。", ["、", "。", "?", "!", None])],
]

# 濁点・半濁点・小文字の切り替えの輪(Kana.swift の KanaModifier と同じ)
_CYCLES = [list(p) for p in ["かが", "きぎ", "くぐ", "けげ", "こご", "さざ", "しじ", "すず", "せぜ", "そぞ",
                              "ただ", "ちぢ", "てで", "とど", "つっづ", "はばぱ", "ひびぴ", "ふぶぷ", "へべぺ", "ほぼぽ",
                              "あぁ", "いぃ", "えぇ", "おぉ", "やゃ", "ゆゅ", "よょ", "わゎ", "うぅゔ"]]


def base_of(kana: str) -> str:
    """濁点などを外した元の仮名"""
    for cycle in _CYCLES:
        if kana in cycle[1:]:
            return cycle[0]
    return kana


def position(kana: str):
    """仮名 → (キーの表示名, 方向の番号)。無ければ None"""
    kana = base_of(kana)
    for row in FLICK_ROWS:
        for label, outputs in row:
            if kana in outputs:
                return label, outputs.index(kana)
    return None


def evaluate_flick(prompts: list[dict], taps: list[dict], final_text: str | None) -> dict:
    flicks = sorted((t for t in taps if t.get("flickDirection") is not None), key=lambda t: t["t"])
    by_prompt: dict[int, list[dict]] = {}
    for f in flicks:
        if f.get("promptIndex") is not None:
            by_prompt.setdefault(f["promptIndex"], []).append(f)

    matched = key_ok = dir_ok = kana_ok = 0
    confusion = [[0] * 5 for _ in DIRECTIONS]
    for p in prompts:
        truth = position(p["target"])
        got = by_prompt.get(p["index"])
        if not got or truth is None:
            continue
        first = got[0]
        matched += 1
        key_ok += first.get("flickKey") == truth[0]
        dir_ok += first["flickDirection"] == truth[1]
        kana_ok += first.get("output") == base_of(p["target"])
        confusion[truth[1]][first["flickDirection"]] += 1

    ref = "".join(p["target"] for p in prompts)
    hyp = (final_text or "").replace("\n", "")
    duration = flicks[-1]["t"] - flicks[0]["t"] if len(flicks) >= 2 else 0
    n = max(matched, 1)
    return {
        "recall": matched / max(len(prompts), 1),
        "precision": matched / max(len(flicks), 1),
        "key_accuracy": key_ok / n,
        "direction_accuracy": dir_ok / n,
        "kana_accuracy": kana_ok / n,
        "cer": edit_distance(hyp, ref) / max(len(ref), 1),
        "cpm": len(hyp) / (duration / 60) if duration > 0 else 0.0,
        "confusion": confusion,
        "hypothesis": hyp,
        "reference": ref,
    }
