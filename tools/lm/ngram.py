"""文字 n-gram 言語モデル(Witten-Bell 補間)の Python 版。

Swift 版(ARKeyboard/Core/CharNGramModel.swift)と同じ計算をする「参照実装」です。
アルゴリズムはまず Python で試し、評価してから Swift に移す、という方針のため、
両方の出力が一致することをゴールデンテストで確かめます。

    P(c | h) = (C(h,c) + T(h) * P(c | h[1:])) / (C(h) + T(h))
    P(c | "") = (C(c) + 1) / (N + V)
"""
from __future__ import annotations

import math
from collections import defaultdict

VOCABULARY = list("abcdefghijklmnopqrstuvwxyz ,.;")
_ALLOWED = set(VOCABULARY)


def normalize(text: str) -> str:
    """小文字化、改行・タブはスペースへ、打てない文字は削除、連続スペースは1つに。"""
    out = []
    last_space = False
    for ch in text.lower():
        c = " " if ch in "\n\t\r" else ch
        if c not in _ALLOWED:
            continue
        if c == " ":
            if last_space:
                continue
            last_space = True
        else:
            last_space = False
        out.append(c)
    return "".join(out)


class CharNGramModel:
    def __init__(self, text: str, order: int = 5):
        self.order = max(1, order)
        self.counts: dict[str, dict[str, int]] = defaultdict(lambda: defaultdict(int))
        self.totals: dict[str, int] = defaultdict(int)
        chars = normalize(text)
        for i, c in enumerate(chars):
            for n in range(self.order):
                if i - n < 0:
                    break
                ctx = chars[i - n:i]
                self.counts[ctx][c] += 1
                self.totals[ctx] += 1

    def probability(self, c: str, context: str) -> float:
        ctx = normalize(context)
        k = min(self.order - 1, len(ctx))
        history = ctx[len(ctx) - k:] if k > 0 else ""
        return self._interpolated(c, history)

    def log_probability(self, c: str, context: str) -> float:
        return math.log(max(self.probability(c, context), 1e-300))

    def _interpolated(self, c: str, history: str) -> float:
        if history == "":
            count = self.counts[""].get(c, 0) if "" in self.counts else 0
            total = self.totals.get("", 0)
            return (count + 1) / (total + len(VOCABULARY))
        shorter = self._interpolated(c, history[1:])
        total = self.totals.get(history, 0)
        nxt = self.counts.get(history)
        if total == 0 or not nxt:
            return shorter
        types = len(nxt)
        return (nxt.get(c, 0) + types * shorter) / (total + types)
