"""タップ推定レベルB: 小さなニューラルネットワークを学習して、アプリで使える形に書き出す。

入力(22 個の特徴量)は、再生コマンドが書き出したタップ候補の特徴量(ARKeyboard/Core/TapClassifier.swift の TapFeatures)。
出力は 3 つ: [タップらしさ(ロジット), 位置の補正 dx, dy]。

使い方(Mac、リポジトリのルートで):
    swift build -c release --product arkeyboard-replay     # 初回だけ
    python3 tools/eval/train_levelb.py recordings/*.json --out ARKeyboard/Resources/Model/
        → LevelBTapModel.json(Swift でそのまま計算できる重み)
        → LevelBTapModel.mlmodel(coremltools が入っていれば。Core ML 用)
    アプリに入れるには、出力されたファイルを ARKeyboard/Resources/Model/ に置いてビルドし直し、
    設定 → タップ推定レベルB をオンにする。

必要なもの: numpy(pip install numpy)。Core ML 形式にするなら coremltools(pip install coremltools)。

## 正解ラベルの付け方
- 合成データ(本当に触れた時刻が分かる): 候補の時刻が、本当に触れた時刻から 80ms 以内なら「タップ」。
- 実際の記録(触れた時刻は分からない): 目標の時間窓ごとに、音のオンセットに最も近い候補
  (音が無ければ、下ろす勢いが最大の候補)を「タップ」、窓の中のほかの候補を「タップでない」とする近似。
  ※ この近似は「1つの目標につき、本物のタップは1回」という仮定に基づく。打ち直しが多い記録では誤りが混ざる。
"""
from __future__ import annotations

import argparse
import json
import os
import shlex
import subprocess
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
FEATURE_COUNT = 22

# 学習データを集めるときの設定: 音を「証拠」として対応づけるが、却下はしない(全部の候補の特徴量がほしい)
COLLECT_PATCH = {"features": {"audioOnset": True, "levelBModel": False, "decoder": True, "wordDecoder": False}}


def default_replay_cmd() -> list[str]:
    built = os.path.join(ROOT, ".build", "release", "arkeyboard-replay")
    return [built] if os.path.exists(built) else ["swift", "run", "-c", "release", "arkeyboard-replay"]


def collect(cmd: list[str], recording: str) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    out = subprocess.run(cmd + ["replay", recording, "--dump-features", "--patch", json.dumps(COLLECT_PATCH)],
                         check=True, capture_output=True, text=True, cwd=ROOT)
    taps = [t for t in json.loads(out.stdout)["taps"] if t.get("features") and len(t["features"]) == FEATURE_COUNT]
    labels = label(taps)
    x = np.array([t["features"] for t in taps], dtype=np.float64)
    y = np.array(labels, dtype=np.float64)
    offsets = np.array([[t["targetOffset"]["x"], t["targetOffset"]["y"]] if t.get("targetOffset") else [0.0, 0.0]
                        for t in taps], dtype=np.float64)
    has_offset = np.array([1.0 if t.get("targetOffset") else 0.0 for t in taps])
    return x, y, offsets, has_offset


def label(taps: list[dict]) -> list[int]:
    if taps and all("truthDistance" in t for t in taps):
        return [1 if t["truthDistance"] < 0.08 else 0 for t in taps]
    # 実際の記録: 目標の窓ごとに1つだけ「タップ」
    labels = [0] * len(taps)
    by_prompt: dict[int, list[int]] = {}
    for i, t in enumerate(taps):
        if t.get("promptIndex") is not None:
            by_prompt.setdefault(t["promptIndex"], []).append(i)
    for indices in by_prompt.values():
        with_audio = [i for i in indices if taps[i]["features"][19] > 0]
        if with_audio:
            best = min(with_audio, key=lambda i: abs(taps[i]["features"][21]))
        else:
            best = max(indices, key=lambda i: taps[i]["features"][12])
        labels[best] = 1
    return labels


class MLP:
    """22 → 16 → 3 の全結合ネットワーク(ReLU)。numpy だけで学習する。"""

    def __init__(self, sizes=(FEATURE_COUNT, 16, 3), seed=0):
        rng = np.random.default_rng(seed)
        self.w = [rng.normal(0, np.sqrt(2 / a), (b, a)) for a, b in zip(sizes[:-1], sizes[1:])]
        self.b = [np.zeros(b) for b in sizes[1:]]

    def forward(self, x):
        acts = [x]
        h = x
        for i, (w, b) in enumerate(zip(self.w, self.b)):
            z = h @ w.T + b
            h = np.maximum(z, 0) if i < len(self.w) - 1 else z
            acts.append(h)
        return acts

    def train(self, x, y, offsets, mask, epochs=400, lr=0.01, offset_weight=1.0):
        # Adam(学習の歩幅を自動で調整する最適化の方法)
        params = self.w + self.b
        m = [np.zeros_like(p) for p in params]
        v = [np.zeros_like(p) for p in params]
        pos_weight = max((len(y) - y.sum()) / max(y.sum(), 1), 1.0)  # タップが少ないときに重みを付ける
        for epoch in range(1, epochs + 1):
            acts = self.forward(x)
            out = acts[-1]
            prob = 1 / (1 + np.exp(-out[:, 0]))
            weights = np.where(y == 1, pos_weight, 1.0)
            grad_out = np.zeros_like(out)
            grad_out[:, 0] = (prob - y) * weights / len(y)
            reg_mask = (mask * y)[:, None]
            grad_out[:, 1:] = offset_weight * 2 * (out[:, 1:] - offsets) * reg_mask / max(reg_mask.sum(), 1)
            grads_w, grads_b = [], []
            g = grad_out
            for i in reversed(range(len(self.w))):
                grads_w.insert(0, g.T @ acts[i])
                grads_b.insert(0, g.sum(axis=0))
                if i > 0:
                    g = (g @ self.w[i]) * (acts[i] > 0)
            grads = grads_w + grads_b
            for k, (p, gr) in enumerate(zip(params, grads)):
                m[k] = 0.9 * m[k] + 0.1 * gr
                v[k] = 0.999 * v[k] + 0.001 * gr * gr
                mh = m[k] / (1 - 0.9 ** epoch)
                vh = v[k] / (1 - 0.999 ** epoch)
                p -= lr * mh / (np.sqrt(vh) + 1e-8)

    def predict(self, x):
        out = self.forward(x)[-1]
        return 1 / (1 + np.exp(-out[:, 0])), out[:, 1:]


def export_json(model: MLP, mean, std, path: str) -> None:
    layers = []
    for i, (w, b) in enumerate(zip(model.w, model.b)):
        layers.append({"weights": w.tolist(), "bias": b.tolist(),
                       "activation": "relu" if i < len(model.w) - 1 else "linear"})
    with open(path, "w", encoding="utf-8") as f:
        json.dump({"inputMean": mean.tolist(), "inputStd": std.tolist(), "layers": layers}, f)


def export_coreml(model: MLP, mean, std, path: str) -> bool:
    """coremltools があれば Core ML の形式(.mlmodel)にする。標準化も最初の層に含める。"""
    try:
        import coremltools as ct  # noqa: F401
        from coremltools.models import datatypes
        from coremltools.models.neural_network import NeuralNetworkBuilder
    except ImportError:
        print("coremltools が無いので .mlmodel は作りません(pip install coremltools)", file=sys.stderr)
        return False
    # 標準化 (x - mean) / std を最初の層の重みに畳み込む
    w0 = model.w[0] / std[None, :]
    b0 = model.b[0] - (model.w[0] * (mean / std)[None, :]).sum(axis=1)
    builder = NeuralNetworkBuilder([("features", datatypes.Array(FEATURE_COUNT))],
                                   [("output", datatypes.Array(3))])
    builder.add_inner_product("fc0", W=w0, b=b0, input_channels=FEATURE_COUNT, output_channels=w0.shape[0],
                              has_bias=True, input_name="features", output_name="h0")
    builder.add_activation("relu0", "RELU", "h0", "a0")
    builder.add_inner_product("fc1", W=model.w[1], b=model.b[1], input_channels=w0.shape[0], output_channels=3,
                              has_bias=True, input_name="a0", output_name="output")
    import coremltools
    mlmodel = coremltools.models.MLModel(builder.spec)
    mlmodel.short_description = "ARKeyboard タップ推定レベルB(タップらしさのロジット, dx, dy)"
    mlmodel.save(path)
    return True


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("recordings", nargs="+")
    parser.add_argument("--out", default=os.path.join(ROOT, "ARKeyboard", "Resources", "Model"))
    parser.add_argument("--replay-cmd")
    parser.add_argument("--epochs", type=int, default=400)
    parser.add_argument("--golden", help="Swift とのゴールデンテスト用の固定データの出力先")
    args = parser.parse_args()
    cmd = shlex.split(args.replay_cmd) if args.replay_cmd else default_replay_cmd()

    xs, ys, offs, masks = [], [], [], []
    for rec in args.recordings:
        x, y, o, m = collect(cmd, rec)
        xs.append(x); ys.append(y); offs.append(o); masks.append(m)
        print(f"{os.path.basename(rec)}: 候補 {len(y)}, タップ {int(y.sum())}", file=sys.stderr)
    x = np.concatenate(xs); y = np.concatenate(ys); offsets = np.concatenate(offs); mask = np.concatenate(masks)

    mean = x.mean(axis=0)
    std = x.std(axis=0)
    std[std < 1e-6] = 1.0
    xn = (x - mean) / std

    # 8:2 に分けて、学習に使っていないデータで確かめる
    rng = np.random.default_rng(1)
    order = rng.permutation(len(y))
    split = int(len(y) * 0.8)
    tr, va = order[:split], order[split:]
    model = MLP()
    model.train(xn[tr], y[tr], offsets[tr], mask[tr], epochs=args.epochs)
    prob, _ = model.predict(xn[va])
    pred = prob >= 0.5
    tp = int((pred & (y[va] == 1)).sum()); fp = int((pred & (y[va] == 0)).sum()); fn = int((~pred & (y[va] == 1)).sum())
    precision = tp / max(tp + fp, 1); recall = tp / max(tp + fn, 1)
    print(f"検証データ: 適合率 {precision:.3f} 再現率 {recall:.3f}(候補 {len(va)})", file=sys.stderr)

    os.makedirs(args.out, exist_ok=True)
    json_path = os.path.join(args.out, "LevelBTapModel.json")
    export_json(model, mean, std, json_path)
    print(f"wrote {json_path}", file=sys.stderr)
    export_coreml(model, mean, std, os.path.join(args.out, "LevelBTapModel.mlmodel"))

    if args.golden:
        sample = x[:10]
        out = model.forward((sample - mean) / std)[-1]
        with open(args.golden, "w", encoding="utf-8") as f:
            json.dump({"model": json.load(open(json_path)), "inputs": sample.tolist(), "outputs": out.tolist()}, f)
        print(f"wrote {args.golden}", file=sys.stderr)


if __name__ == "__main__":
    main()
