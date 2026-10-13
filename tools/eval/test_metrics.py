"""評価指標の単体テスト:  python3 -m unittest discover -s tools/eval"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(__file__))
from metrics import edit_distance, evaluate, finger_for  # noqa: E402
from flick_metrics import base_of, evaluate_flick, position  # noqa: E402


class MetricsTests(unittest.TestCase):
    def test_edit_distance(self):
        self.assertEqual(edit_distance("kitten", "sitting"), 3)
        self.assertEqual(edit_distance("", "abc"), 3)

    def test_finger(self):
        self.assertEqual(finger_for("f"), "left-index")
        self.assertEqual(finger_for(";"), "right-little")
        self.assertEqual(finger_for(" "), "thumb")

    def test_evaluate(self):
        prompts = [{"target": "a", "shownAt": 0.0}, {"target": "b", "shownAt": 1.0}, {"target": "c", "shownAt": 2.0}]
        taps = [
            {"t": 0.3, "accepted": True, "output": "a"},
            {"t": 0.5, "accepted": True, "output": "a"},   # 余計な入力
            {"t": 1.3, "accepted": True, "output": "v"},   # キーの誤り
            {"t": 1.6, "accepted": False, "output": None},  # 却下(数えない)
        ]
        m = evaluate(prompts, taps)
        self.assertAlmostEqual(m["precision"], 2 / 3)
        self.assertAlmostEqual(m["recall"], 2 / 3)
        self.assertAlmostEqual(m["key_accuracy"], 1 / 2)
        self.assertEqual(m["hypothesis"], "aav")
        self.assertAlmostEqual(m["cer"], 2 / 3)


class FlickMetricsTests(unittest.TestCase):
    def test_position(self):
        # Kana.swift の FlickLayout と同じ(KanaTests.testLayoutPositions と同じ例)
        self.assertEqual(position("な"), ("な", 0))
        self.assertEqual(position("に"), ("な", 1))
        self.assertEqual(position("お"), ("あ", 4))
        self.assertEqual(position("ぎ"), ("か", 1))
        self.assertEqual(base_of("ぱ"), "は")
        self.assertEqual(position("。"), ("、。", 1))

    def test_evaluate_flick(self):
        prompts = [{"index": 0, "target": "が"}, {"index": 1, "target": "に"}, {"index": 2, "target": "う"}]
        taps = [
            {"t": 1.0, "flickDirection": 0, "flickKey": "か", "output": "か", "promptIndex": 0},
            {"t": 2.0, "flickDirection": 3, "flickKey": "な", "output": "ね", "promptIndex": 1},  # 方向の誤り
            {"t": 2.2, "flickDirection": 0, "flickKey": "な", "output": "な", "promptIndex": 1},  # 余計
            {"t": 3.0, "output": None, "promptIndex": 1},  # 機能パッド(数えない)
        ]
        m = evaluate_flick(prompts, taps, "がねな")
        self.assertAlmostEqual(m["recall"], 2 / 3)
        self.assertAlmostEqual(m["precision"], 2 / 3)
        self.assertAlmostEqual(m["key_accuracy"], 1.0)
        self.assertAlmostEqual(m["direction_accuracy"], 0.5)
        self.assertAlmostEqual(m["kana_accuracy"], 0.5)
        self.assertEqual(m["confusion"][1][3], 1)
        self.assertAlmostEqual(m["cer"], 2 / 3)


if __name__ == "__main__":
    unittest.main()
