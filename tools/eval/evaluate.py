"""記録データで、アルゴリズムの組み合わせ(バリアント)を比べて表にする。

使い方(Mac、リポジトリのルートで):
    # 1. 再生コマンドをビルド(初回だけ)
    swift build -c release --product arkeyboard-replay
    # 2. 記録ファイル(iPhone から AirDrop したもの)を評価して docs/results.md を作る
    python3 tools/eval/evaluate.py recordings/*.json
    # 記録が無いときの動作確認(合成データを作って評価する)
    python3 tools/eval/evaluate.py --synthetic

外部ライブラリは使いません(Python 3.9 以上の標準ライブラリのみ)。
"""
from __future__ import annotations

import argparse
import datetime
import json
import os
import shlex
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(__file__))
from metrics import evaluate  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))

# 比べる組み合わせ。patch はアプリの設定(KeyboardSettings)への上書き
VARIANTS = [
    ("ルールのみ(カメラ)", {"features": {"audioOnset": False, "motionAssist": False, "decoder": False,
                                      "personalAdaptation": False, "levelBModel": False, "wordDecoder": False}}),
    ("+音(二重条件)", {"features": {"audioOnset": True, "decoder": False, "personalAdaptation": False,
                                   "levelBModel": False, "wordDecoder": False}}),
    ("+音+デコーダー(位置と指のみ)", {"features": {"audioOnset": True, "decoder": True, "languageModel": False,
                                          "personalAdaptation": False, "levelBModel": False, "wordDecoder": False}}),
    ("+音+デコーダー+言語モデル", {"features": {"audioOnset": True, "decoder": True, "languageModel": True,
                                           "personalAdaptation": False, "levelBModel": False, "wordDecoder": False}}),
    ("+音+デコーダー+言語モデル+個人適応", {"features": {"audioOnset": True, "decoder": True, "languageModel": True,
                                                "personalAdaptation": True, "levelBModel": False,
                                                "wordDecoder": False}}),
    ("+音+デコーダー+言語モデル+個人適応+単語デコード", {"features": {"audioOnset": True, "decoder": True,
                                                       "languageModel": True, "personalAdaptation": True,
                                                       "levelBModel": False, "wordDecoder": True}}),
]


def default_replay_cmd() -> list[str]:
    built = os.path.join(ROOT, ".build", "release", "arkeyboard-replay")
    if os.path.exists(built):
        return [built]
    return ["swift", "run", "-c", "release", "arkeyboard-replay"]


def replay(cmd: list[str], recording: str, name: str, patch: dict, noise: float = 0.0,
           extra: list[str] | None = None) -> dict:
    args = cmd + ["replay", recording, "--variant", name, "--patch", json.dumps(patch),
                  "--noise", str(noise)] + (extra or [])
    out = subprocess.run(args, check=True, capture_output=True, text=True, cwd=ROOT)
    return json.loads(out.stdout)


def synthesize(cmd: list[str], path: str, seed: int, mode: str, text: str | None = None,
               finger_bias: float = 0.0) -> None:
    extra = (["--text", text] if text else []) + ["--finger-bias", str(finger_bias)]
    subprocess.run(cmd + ["synth", "--out", path, "--seed", str(seed), "--mode", mode] + extra,
                   check=True, capture_output=True, text=True, cwd=ROOT)


def pct(x: float) -> str:
    return f"{x * 100:.1f}%"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("recordings", nargs="*", help="記録ファイル(.json)")
    parser.add_argument("--synthetic", action="store_true", help="合成データを作って評価する(動作確認用)")
    parser.add_argument("--out", default=os.path.join(ROOT, "docs", "results.md"))
    parser.add_argument("--replay-cmd", help="再生コマンド(既定: .build/release/arkeyboard-replay)")
    parser.add_argument("--model", help="レベルB のモデル(DenseNetwork の JSON)。あればバリアントに追加")
    parser.add_argument("--noise-levels", default="0,0.01,0.02,0.04", help="ぶれへの強さを調べる、人工的なぶれの大きさ")
    args = parser.parse_args()

    cmd = shlex.split(args.replay_cmd) if args.replay_cmd else default_replay_cmd()
    recordings = list(args.recordings)
    synthetic = args.synthetic or not recordings
    tmpdir = None
    if synthetic:
        # 合成データはリポジトリの中の一時フォルダに作る(再生コマンドから見える場所にするため)
        tmpdir = tempfile.mkdtemp(prefix="synth-", dir=os.path.join(ROOT, "tools", "eval"))
        # 1〜3: 練習モードのお題(「asdf jkl;」などの英語でない並びを含む。言語モデルの学習データと一部重なる)
        for seed, mode in [(1, "knee"), (2, "desk"), (3, "knee")]:
            path = os.path.relpath(os.path.join(tmpdir, f"synthetic-{seed}-{mode}.json"), ROOT)
            synthesize(cmd, path, seed, mode)
            recordings.append(path)
        # 5: 指ごとの押し癖(いつも同じ方向に 0.35 キーずれる)がある人(個人適応の効果を見るため)
        path = os.path.relpath(os.path.join(tmpdir, "synthetic-5-knee-bias.json"), ROOT)
        long_text = " ".join([open(os.path.join(ROOT, "tools", "eval", "texts", "heldout_english.txt"),
                                   encoding="utf-8").read()] * 3)
        synthesize(cmd, path, 5, "knee", long_text, finger_bias=0.35)
        recordings.append(path)
        # 4: 言語モデルの学習データに含まれない英文(言語モデルの効果を公平に測るため)
        with open(os.path.join(ROOT, "tools", "eval", "texts", "heldout_english.txt"), encoding="utf-8") as f:
            heldout = f.read()
        path = os.path.relpath(os.path.join(tmpdir, "synthetic-4-knee-heldout.json"), ROOT)
        synthesize(cmd, path, 4, "knee", heldout)
        recordings.append(path)

    variants = list(VARIANTS)
    if args.model:
        variants.append(("+音+デコーダー+言語モデル+レベルB", {"features": {"audioOnset": True, "decoder": True,
                                                                   "languageModel": True, "levelBModel": True}}))

    rows = []
    for rec in recordings:
        with open(os.path.join(ROOT, rec) if not os.path.isabs(rec) else rec, encoding="utf-8") as f:
            prompts = json.load(f)["prompts"]
        for name, patch in variants:
            extra = ["--model", args.model] if (args.model and "レベルB" in name) else []
            result = replay(cmd, rec, name, patch, extra=extra)
            m = evaluate(prompts, result["taps"], result.get("finalText"))
            rows.append((os.path.basename(rec), name, m))
            print(f"{os.path.basename(rec)} / {name}: precision {pct(m['precision'])} recall {pct(m['recall'])} "
                  f"key {pct(m['key_accuracy'])} CER {pct(m['cer'])}", file=sys.stderr)

    # ぶれへの強さ: いちばん機能の多いバリアントと、ルールのみで、人工的なぶれを加えて比べる
    noise_rows = []
    noise_levels = [float(x) for x in args.noise_levels.split(",") if x]
    for rec in recordings[:1]:
        with open(os.path.join(ROOT, rec) if not os.path.isabs(rec) else rec, encoding="utf-8") as f:
            prompts = json.load(f)["prompts"]
        for name, patch in [variants[0], variants[3]]:
            for noise in noise_levels:
                result = replay(cmd, rec, name, patch, noise=noise)
                noise_rows.append((name, noise, evaluate(prompts, result["taps"], result.get("finalText"))))

    # 言語モデルの重み w を変えたときの比較(最後の記録 = 合成なら学習データに無い英文)
    weight_rows = []
    for rec in recordings[-1:]:
        with open(os.path.join(ROOT, rec) if not os.path.isabs(rec) else rec, encoding="utf-8") as f:
            prompts = json.load(f)["prompts"]
        for w in [0.0, 0.3, 0.5, 0.7, 1.0, 1.5]:
            patch = {"features": {"audioOnset": True, "decoder": True, "languageModel": True,
                                  "personalAdaptation": False, "levelBModel": False, "wordDecoder": False},
                     "decoder": {"lmWeight": w}}
            result = replay(cmd, rec, f"w={w}", patch)
            weight_rows.append((w, evaluate(prompts, result["taps"], result.get("finalText"))))

    write_report(args.out, rows, noise_rows, synthetic, recordings, weight_rows)
    print(f"wrote {args.out}", file=sys.stderr)


def write_report(path: str, rows, noise_rows, synthetic: bool, recordings: list[str], weight_rows=()) -> None:
    today = datetime.date.today().isoformat()
    lines = [
        "# 評価結果(docs/results.md)",
        "",
        f"作成日: {today}(`python3 tools/eval/evaluate.py` で自動生成)",
        "",
    ]
    if synthetic:
        lines += [
            "> ⚠️ **この表は合成データ(人工的に作った手の動き)による結果です。実際の利用者の性能ではありません。**",
            "> 評価ツールが正しく動くことの確認と、「どの機能がどの種類の誤りに効くか」の見通しのためのものです。",
            "> 実機の記録モードで集めたデータで `python3 tools/eval/evaluate.py recordings/*.json` を実行して、",
            "> この表を置き換えてください。",
            "",
            "合成データの作り方: `ARKeyboard/Core/SyntheticRecordingGenerator.swift`(狙いのずれ σ=0.25 キー、",
            "関節の震え、フレーム落ち 1%、音の取りこぼし 5%、雑音のオンセット 0.3 回/秒、キーへの移動で手首方向に動く)。",
            "",
        ]
    lines += [
        "## 指標の意味",
        "",
        "- **適合率**: 入力された文字のうち、本当に打ったタップによるものの割合(余計な入力が少ないほど高い)",
        "- **再現率**: 打ってほしかった文字のうち、何か入力されたものの割合(取りこぼしが少ないほど高い)",
        "- **キー正解率**: 本当に打ったタップのうち、正しいキーになった割合",
        "- **CER**: 文字誤り率(入力された文字列と目標の編集距離 ÷ 目標の長さ)。低いほど良い",
        "- **推定WPM**: 入力された文字数 ÷ 5 ÷ 分",
        "",
        "## 組み合わせごとの比較",
        "",
        "| 記録 | 組み合わせ | 適合率 | 再現率 | キー正解率 | CER | 推定WPM | 誤りの多い指 |",
        "|---|---|---|---|---|---|---|---|",
    ]
    for rec, name, m in rows:
        fingers = ", ".join(f"{k}:{v}" for k, v in sorted(m["finger_errors"].items(), key=lambda kv: -kv[1])[:3])
        lines.append(f"| {rec} | {name} | {pct(m['precision'])} | {pct(m['recall'])} | {pct(m['key_accuracy'])} | "
                     f"{pct(m['cer'])} | {m['wpm']:.1f} | {fingers or '-'} |")
    if noise_rows:
        lines += [
            "",
            "## 位置のぶれへの強さ(人工的なぶれを加えた場合)",
            "",
            "関節点に、手の大きさに対する標準偏差でガウス雑音を加えて再生した結果(最初の記録のみ)。",
            "",
            "| 組み合わせ | ぶれ(手の大きさ比) | 適合率 | 再現率 | キー正解率 | CER |",
            "|---|---|---|---|---|---|",
        ]
        for name, noise, m in noise_rows:
            lines.append(f"| {name} | {noise} | {pct(m['precision'])} | {pct(m['recall'])} | "
                         f"{pct(m['key_accuracy'])} | {pct(m['cer'])} |")
    if weight_rows:
        lines += [
            "",
            "## 言語モデルの重み w の比較(最後の記録)",
            "",
            "| w | キー正解率 | CER |",
            "|---|---|---|",
        ]
        for w, m in weight_rows:
            lines.append(f"| {w} | {pct(m['key_accuracy'])} | {pct(m['cer'])} |")
    lines += [
        "",
        "## 入力された文字列の例(最初の記録)",
        "",
    ]
    if rows:
        first = rows[0][0]
        lines.append(f"- 目標: `{rows[0][2]['reference']}`")
        for rec, name, m in rows:
            if rec == first:
                lines.append(f"- {name}: `{m['hypothesis']}`")
    lines += ["", f"記録ファイル: {', '.join(os.path.basename(r) for r in recordings)}", ""]
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))


if __name__ == "__main__":
    main()
