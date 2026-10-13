"""オンセット検出(適応しきい値)の Python 版。Swift 版 ARKeyboard/Core/OnsetDetector.swift と同じ計算。

しきい値 = 直近 historyDuration 秒の中央値 + k × max(MAD × 1.4826, minSpread)
しきい値を下から上へ越えた瞬間(かつ不応期の外)をオンセットとする。
"""
from __future__ import annotations


def median(values: list[float]) -> float:
    if not values:
        return 0.0
    s = sorted(values)
    m = len(s) // 2
    return (s[m - 1] + s[m]) / 2 if len(s) % 2 == 0 else s[m]


class OnsetDetector:
    def __init__(self, k: float = 6.0, min_spread: float = 1e-4, history_duration: float = 0.5,
                 refractory: float = 0.06):
        self.k = k
        self.min_spread = min_spread
        self.history_duration = history_duration
        self.refractory = refractory
        self.history: list[tuple[float, float]] = []
        self.was_above = False
        self.last_onset = float("-inf")
        self.last_threshold = 0.0

    def process(self, value: float, time: float):
        oldest = time - self.history_duration
        self.history = [h for h in self.history if h[0] >= oldest]
        event = None
        if len(self.history) >= 8:
            values = [h[1] for h in self.history]
            med = median(values)
            mad = median([abs(v - med) for v in values]) * 1.4826
            threshold = med + self.k * max(mad, self.min_spread)
            self.last_threshold = threshold
            above = value > threshold
            if above and not self.was_above and time - self.last_onset >= self.refractory:
                event = {"time": time, "strength": value / threshold}
                self.last_onset = time
            self.was_above = above
        self.history.append((time, value))
        return event
