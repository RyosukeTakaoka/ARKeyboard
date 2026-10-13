"""フリック入力(7-4)の評価: 組み合わせの比較、方向の混同行列、位置のぶれに対する QWERTY との比較。

使い方(Mac、リポジトリのルートで):
    swift build -c release --product arkeyboard-replay
    # 実機の「仮名(フリック)」の記録を評価する
    python3 tools/eval/evaluate_flick.py recordings/kana-*.json
    # 記録が無いときの動作確認(合成データを作って評価する)→ docs/results-flick.md
    python3 tools/eval/evaluate_flick.py --synthetic

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
from evaluate import ROOT, default_replay_cmd, pct, replay, synthesize  # noqa: E402
from flick_metrics import DIRECTIONS, evaluate_flick  # noqa: E402
from metrics import evaluate  # noqa: E402

NO_ADAPT = {"personalAdaptation": False}
VARIANTS = [
    ("方式A(位置と方向のみ)", {"features": NO_ADAPT, "flick": {"useLanguageModel": False}}),
    ("方式A+仮名の言語モデル", {"features": NO_ADAPT, "flick": {"useLanguageModel": True}}),
    ("方式A+仮名の言語モデル+方向の個人適応", {"features": {"personalAdaptation": True},
                                       "flick": {"useLanguageModel": True}}),
]
# ぶれ除去フィルター(One Euro)をオンにした組み合わせ(フィルターで速さの山が低くなるので、しきい値も下げる)
FILTER_PATCH = {"features": NO_ADAPT, "flick": {"useLanguageModel": True, "useJitterFilter": True,
                                                "filterMinCutoff": 1.5, "filterBeta": 3.0,
                                                "startSpeed": 1.2, "endSpeed": 0.5}}
# QWERTY 側の比較相手(evaluate.py の「+音+デコーダー+言語モデル」と同じ)
QWERTY_PATCH = {"features": {"audioOnset": True, "decoder": True, "languageModel": True,
                             "personalAdaptation": False, "levelBModel": False, "wordDecoder": False}}


def synthesize_flick(cmd: list[str], path: str, seed: int, text: str, rotation_bias: float = 0.0,
                     extra: list[str] | None = None) -> None:
    subprocess.run(cmd + ["synth", "--flick", "--out", path, "--seed", str(seed), "--text", text,
                          "--rotation-bias", str(rotation_bias)] + (extra or []),
                   check=True, capture_output=True, text=True, cwd=ROOT)


def load_prompts(rec: str) -> list[dict]:
    with open(os.path.join(ROOT, rec) if not os.path.isabs(rec) else rec, encoding="utf-8") as f:
        return json.load(f)["prompts"]


def run(cmd, rec, name, patch, noise=0.0) -> dict:
    result = replay(cmd, rec, name, patch, noise=noise)
    m = evaluate_flick(load_prompts(rec), result["taps"], result.get("finalText"))
    print(f"{os.path.basename(rec)} / {name} / noise {noise}: key {pct(m['key_accuracy'])} "
          f"dir {pct(m['direction_accuracy'])} CER {pct(m['cer'])}", file=sys.stderr)
    return m


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("recordings", nargs="*", help="仮名(フリック)の記録ファイル(.json)")
    parser.add_argument("--synthetic", action="store_true", help="合成データを作って評価する(動作確認用)")
    parser.add_argument("--qwerty", help="位置のぶれの比較に使う QWERTY の記録(省略時は合成)")
    parser.add_argument("--out", default=os.path.join(ROOT, "docs", "results-flick.md"))
    parser.add_argument("--replay-cmd", help="再生コマンド(既定: .build/release/arkeyboard-replay)")
    parser.add_argument("--noise-levels", default="0,0.01,0.02,0.03,0.04")
    args = parser.parse_args()

    cmd = shlex.split(args.replay_cmd) if args.replay_cmd else default_replay_cmd()
    recordings = list(args.recordings)
    synthetic = args.synthetic or not recordings
    qwerty = args.qwerty
    bias_rec = None
    if synthetic:
        tmpdir = tempfile.mkdtemp(prefix="synth-flick-", dir=os.path.join(ROOT, "tools", "eval"))
        texts = os.path.join(ROOT, "tools", "eval", "texts")
        kana = open(os.path.join(texts, "heldout_kana.txt"), encoding="utf-8").read()
        for seed in (1, 2):
            path = os.path.relpath(os.path.join(tmpdir, f"synthetic-flick-{seed}.json"), ROOT)
            synthesize_flick(cmd, path, seed, kana)
            recordings.append(path)
        # その人の癖: いつも 25 度回ってしまう(方向の個人適応の効果を見るため。同じ文章を 3 回)
        bias_rec = os.path.relpath(os.path.join(tmpdir, "synthetic-flick-3-bias25.json"), ROOT)
        synthesize_flick(cmd, bias_rec, 3, kana * 3, rotation_bias=25)
        if not qwerty:
            english = open(os.path.join(texts, "heldout_english.txt"), encoding="utf-8").read()
            qwerty = os.path.relpath(os.path.join(tmpdir, "synthetic-qwerty-4.json"), ROOT)
            synthesize(cmd, qwerty, 4, "knee", english)

    rows = [(os.path.basename(rec), name, run(cmd, rec, name, patch))
            for rec in recordings for name, patch in VARIANTS]
    bias_rows = []
    if bias_rec:
        bias_rows = [(name, run(cmd, bias_rec, name, patch)) for name, patch in VARIANTS[1:]]

    # 位置のぶれに対する強さ: 同じ人工的なぶれを加えて、フリック(方式A+言語モデル)と QWERTY を比べる
    noise_levels = [float(x) for x in args.noise_levels.split(",") if x]
    noise_rows = []
    for noise in noise_levels:
        flick = run(cmd, recordings[0], VARIANTS[1][0], VARIANTS[1][1], noise=noise)
        filtered = run(cmd, recordings[0], "+ぶれ除去フィルター", FILTER_PATCH, noise=noise)
        q = None
        if qwerty:
            result = replay(cmd, qwerty, "qwerty", QWERTY_PATCH, noise=noise)
            q = evaluate(load_prompts(qwerty), result["taps"], result.get("finalText"))
        noise_rows.append((noise, flick, filtered, q))

    # 仮名の言語モデルの重み
    weight_rows = []
    for w in [0.0, 0.25, 0.5, 1.0, 2.0]:
        patch = {"features": NO_ADAPT, "flick": {"useLanguageModel": True, "lmWeight": w}}
        weight_rows.append((w, run(cmd, recordings[0], f"w={w}", patch)))

    write_report(args.out, rows, bias_rows, noise_rows, weight_rows, synthetic, recordings)
    print(f"wrote {args.out}", file=sys.stderr)


def write_report(path, rows, bias_rows, noise_rows, weight_rows, synthetic, recordings) -> None:
    lines = [
        "# フリック入力の評価結果(docs/results-flick.md)",
        "",
        f"作成日: {datetime.date.today().isoformat()}(`python3 tools/eval/evaluate_flick.py` で自動生成)",
        "",
    ]
    if synthetic:
        lines += [
            "> ⚠️ **合成データ(人工的に作った指の動き)による結果です。実際の利用者の性能ではありません。**",
            "> さらに、切り出しのしきい値(止まりの速さなど)はこの合成データを見ながら決めたので、",
            "> この表の数値は実力より良く出ている可能性が高いです。実機の「仮名(フリック)」の記録で",
            "> `python3 tools/eval/evaluate_flick.py recordings/*.json` を実行して置き換えてください。",
            "",
            "合成データの作り方: `ARKeyboard/Core/SyntheticFlickGenerator.swift`(30fps、始点の狙いのずれ σ=0.2 キー、",
            "方向のばらつき σ=12 度、フリックの長さ 0.3±0.05 手、キーへの移動は平均 1 手/秒、",
            "濁点・小文字は機能パッドのタップ(音の取りこぼし 5%)、関節の震え、フレーム落ち 1%)。",
            "文章は言語モデルの学習データに無いもの(`tools/eval/texts/heldout_kana.txt`)。",
            "",
        ]
    lines += [
        "## 指標の意味",
        "",
        "- **検出(再現率/適合率)**: 目標の文字ごとにフリックが検出されたか / 検出のうち目標に対応したものの割合",
        "- **始点キー正解率・方向正解率**: 対応したフリックの、始点のキー(行)と方向(タップ・左・上・右・下)が正しかった割合",
        "- **仮名正解率**: そのフリック単独の解読の1位が正しい仮名だった割合(濁点などを除いた元の仮名で比べる)",
        "- **CER**: 最終的な文字列(並びの解読・濁点の付与を反映)の文字誤り率。低いほど良い",
        "- **CPM**: 1分あたりの入力文字数(合成データでは、指の動きの速さを決め打ちしているので参考値)",
        "",
        "## 組み合わせごとの比較(方式A: エアフリック)",
        "",
        "| 記録 | 組み合わせ | 検出 再現率 | 検出 適合率 | 始点キー | 方向 | 仮名 | CER | CPM |",
        "|---|---|---|---|---|---|---|---|---|",
    ]
    for rec, name, m in rows:
        lines.append(f"| {rec} | {name} | {pct(m['recall'])} | {pct(m['precision'])} | {pct(m['key_accuracy'])} | "
                     f"{pct(m['direction_accuracy'])} | {pct(m['kana_accuracy'])} | {pct(m['cer'])} | {m['cpm']:.0f} |")
    lines += [
        "",
        "方式B(接触フリック: 音で始まりを決める)は Tier3 で追加します(このファイルに行が増えます)。",
        "",
    ]
    if bias_rows:
        lines += [
            "## 方向の個人適応(いつも 25 度回ってしまう人の合成データ)",
            "",
            "| 組み合わせ | 方向 | 仮名 | CER |",
            "|---|---|---|---|",
        ]
        for name, m in bias_rows:
            lines.append(f"| {name} | {pct(m['direction_accuracy'])} | {pct(m['kana_accuracy'])} | {pct(m['cer'])} |")
        lines.append("")
    # 混同行列(最初の記録 × 言語モデルあり)
    confusion = next((m["confusion"] for rec, name, m in rows if name == VARIANTS[1][0]), None)
    if confusion:
        lines += [
            "## 方向の混同行列(最初の記録、方式A+仮名の言語モデル)",
            "",
            "行 = 正しい方向、列 = 解読された方向(回数)。",
            "",
            "| 正しい \\ 解読 | " + " | ".join(DIRECTIONS) + " |",
            "|---|" + "---|" * len(DIRECTIONS),
        ]
        for i, d in enumerate(DIRECTIONS):
            lines.append(f"| {d} | " + " | ".join(str(c) for c in confusion[i]) + " |")
        lines.append("")
    if noise_rows:
        lines += [
            "## 位置のぶれへの強さ: QWERTY とフリックの比較",
            "",
            "同じ条件(関節点に、手の大きさに対する標準偏差でガウス雑音を加える)で再生した結果。",
            "QWERTY は英文(evaluate.py の「+音+デコーダー+言語モデル」)、フリックは仮名文(方式A+仮名の言語モデル)。",
            "**文章も言語も違うので、CER の絶対値ではなく「ぶれを増やしたときの悪化の仕方」を比べてください。**",
            "",
            "「+フィルター」は、ぶれ除去フィルター(One Euro)をオンにし、動き出し 1.2・止まり 0.5 手/秒に下げたもの。",
            "",
            "| ぶれ(手の大きさ比) | QWERTY 再現率 | QWERTY キー正解率 | QWERTY CER | フリック 検出 再現率 | フリック 仮名 | フリック CER "
            "| +フィルター 検出 再現率 | +フィルター CER |",
            "|---|---|---|---|---|---|---|---|---|",
        ]
        for noise, f, g, q in noise_rows:
            qcols = (f"{pct(q['recall'])} | {pct(q['key_accuracy'])} | {pct(q['cer'])}" if q else "- | - | -")
            lines.append(f"| {noise} | {qcols} | {pct(f['recall'])} | {pct(f['kana_accuracy'])} | {pct(f['cer'])} "
                         f"| {pct(g['recall'])} | {pct(g['cer'])} |")
        lines.append("")
    if weight_rows:
        lines += [
            "## 仮名の言語モデルの重み(最初の記録)",
            "",
            "| 重み | 方向 | 仮名 | CER |",
            "|---|---|---|---|",
        ]
        for w, m in weight_rows:
            lines.append(f"| {w} | {pct(m['direction_accuracy'])} | {pct(m['kana_accuracy'])} | {pct(m['cer'])} |")
        lines.append("")
    if rows:
        first = rows[0][0]
        lines += ["## 入力された文字列の例(最初の記録)", "", f"- 目標: `{rows[0][2]['reference']}`"]
        lines += [f"- {name}: `{m['hypothesis']}`" for rec, name, m in rows if rec == first]
    lines += ["", f"記録ファイル: {', '.join(os.path.basename(r) for r in recordings)}", ""]
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))


if __name__ == "__main__":
    main()
