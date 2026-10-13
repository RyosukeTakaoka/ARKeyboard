"""評価指標の単体テスト:  python3 -m unittest discover -s tools/eval"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(__file__))
from metrics import edit_distance, evaluate, finger_for  # noqa: E402


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


if __name__ == "__main__":
    unittest.main()
