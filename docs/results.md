# 評価結果(docs/results.md)

作成日: 2026-10-13(`python3 tools/eval/evaluate.py` で自動生成)

> ⚠️ **この表は合成データ(人工的に作った手の動き)による結果です。実際の利用者の性能ではありません。**
> 評価ツールが正しく動くことの確認と、「どの機能がどの種類の誤りに効くか」の見通しのためのものです。
> 実機の記録モードで集めたデータで `python3 tools/eval/evaluate.py recordings/*.json` を実行して、
> この表を置き換えてください。

合成データの作り方: `ARKeyboard/Core/SyntheticRecordingGenerator.swift`(狙いのずれ σ=0.25 キー、
関節の震え、フレーム落ち 1%、音の取りこぼし 5%、雑音のオンセット 0.3 回/秒、キーへの移動で手首方向に動く)。

## 指標の意味

- **適合率**: 入力された文字のうち、本当に打ったタップによるものの割合(余計な入力が少ないほど高い)
- **再現率**: 打ってほしかった文字のうち、何か入力されたものの割合(取りこぼしが少ないほど高い)
- **キー正解率**: 本当に打ったタップのうち、正しいキーになった割合
- **CER**: 文字誤り率(入力された文字列と目標の編集距離 ÷ 目標の長さ)。低いほど良い
- **推定WPM**: 入力された文字数 ÷ 5 ÷ 分

## 組み合わせごとの比較

| 記録 | 組み合わせ | 適合率 | 再現率 | キー正解率 | CER | 推定WPM | 誤りの多い指 |
|---|---|---|---|---|---|---|---|
| synthetic-1-knee.json | ルールのみ(カメラ) | 73.5% | 100.0% | 83.3% | 40.7% | 27.4 | thumb:5, right-index:5, left-index:3 |
| synthetic-1-knee.json | +音(二重条件) | 100.0% | 94.7% | 96.5% | 8.7% | 19.2 | right-middle:1, left-ring:1, left-index:1 |
| synthetic-1-knee.json | +音+デコーダー(位置と指のみ) | 100.0% | 94.7% | 96.5% | 8.7% | 19.2 | right-middle:1, left-ring:1, left-index:1 |
| synthetic-1-knee.json | +音+デコーダー+言語モデル | 100.0% | 94.7% | 93.7% | 11.3% | 19.2 | right-index:4, right-little:3, right-middle:1 |
| synthetic-2-desk.json | ルールのみ(カメラ) | 74.5% | 99.3% | 85.9% | 38.0% | 26.8 | right-index:7, thumb:4, right-ring:3 |
| synthetic-2-desk.json | +音(二重条件) | 100.0% | 96.0% | 98.6% | 5.3% | 19.3 | right-index:2 |
| synthetic-2-desk.json | +音+デコーダー(位置と指のみ) | 100.0% | 96.0% | 98.6% | 5.3% | 19.3 | right-index:2 |
| synthetic-2-desk.json | +音+デコーダー+言語モデル | 100.0% | 96.0% | 97.9% | 6.0% | 19.3 | right-index:1, left-middle:1, right-little:1 |
| synthetic-3-knee.json | ルールのみ(カメラ) | 73.9% | 100.0% | 78.7% | 42.7% | 27.2 | right-index:8, right-ring:5, thumb:5 |
| synthetic-3-knee.json | +音(二重条件) | 99.3% | 95.3% | 95.1% | 10.0% | 19.3 | right-ring:2, right-index:2, right-middle:1 |
| synthetic-3-knee.json | +音+デコーダー(位置と指のみ) | 99.3% | 95.3% | 95.1% | 10.0% | 19.3 | right-ring:2, right-index:2, right-middle:1 |
| synthetic-3-knee.json | +音+デコーダー+言語モデル | 99.3% | 95.3% | 97.2% | 7.3% | 19.3 | left-middle:2, right-ring:1, left-index:1 |
| synthetic-4-knee-heldout.json | ルールのみ(カメラ) | 68.5% | 100.0% | 86.0% | 53.0% | 29.2 | right-index:18, left-index:10, thumb:9 |
| synthetic-4-knee-heldout.json | +音(二重条件) | 98.1% | 97.5% | 95.5% | 8.8% | 19.9 | left-index:6, left-middle:5, right-ring:2 |
| synthetic-4-knee-heldout.json | +音+デコーダー(位置と指のみ) | 98.1% | 97.5% | 95.5% | 8.8% | 19.9 | left-index:6, left-middle:5, right-ring:2 |
| synthetic-4-knee-heldout.json | +音+デコーダー+言語モデル | 98.1% | 97.5% | 98.0% | 6.3% | 19.9 | left-index:6, right-index:1 |

## 位置のぶれへの強さ(人工的なぶれを加えた場合)

関節点に、手の大きさに対する標準偏差でガウス雑音を加えて再生した結果(最初の記録のみ)。

| 組み合わせ | ぶれ(手の大きさ比) | 適合率 | 再現率 | キー正解率 | CER |
|---|---|---|---|---|---|
| ルールのみ(カメラ) | 0.0 | 73.5% | 100.0% | 83.3% | 40.7% |
| ルールのみ(カメラ) | 0.01 | 71.8% | 100.0% | 85.3% | 44.0% |
| ルールのみ(カメラ) | 0.02 | 33.0% | 100.0% | 44.0% | 210.0% |
| ルールのみ(カメラ) | 0.04 | 10.3% | 100.0% | 10.0% | 886.7% |
| +音+デコーダー+言語モデル | 0.0 | 100.0% | 94.7% | 93.7% | 11.3% |
| +音+デコーダー+言語モデル | 0.01 | 99.3% | 94.7% | 93.7% | 11.3% |
| +音+デコーダー+言語モデル | 0.02 | 72.9% | 93.3% | 70.7% | 53.3% |
| +音+デコーダー+言語モデル | 0.04 | 31.1% | 9.3% | 14.3% | 82.0% |

## 言語モデルの重み w の比較(最後の記録)

| w | キー正解率 | CER |
|---|---|---|
| 0.0 | 95.5% | 8.8% |
| 0.3 | 97.7% | 6.6% |
| 0.5 | 97.5% | 6.9% |
| 0.7 | 96.9% | 7.4% |
| 1.0 | 95.2% | 9.1% |
| 1.5 | 94.1% | 10.2% |

## 入力された文字列の例(最初の記録)

- 目標: `asdf jkl; fjfj dkdk sls; a;a; the quick brown fox jumps over the lazy dog. hello, world. type on your knees practice makes perfect. a sad lad asks dad`
- ルールのみ(カメラ): `asdf jkl; fjfj dikdk sls; a;a;; tfhed aaujikck  brfolwsj fols jujmp;s olgedrf tfhed laayj dolg.. hedllol, wsolrflldl tfyjp;ed oln yjolujrf knededs p;rfactfikced makkeds p;edrffeddtf.. a sad lad  askss dad`
- +音(二重条件): `asdf jkl; fjfj didk sls; a;a; th uic brown fos jumps oger the aay do. hello, worldl type on your nees practice makes perfect. a sad ld asks da`
- +音+デコーダー(位置と指のみ): `asdf jkl; fjfj didk sls; a;a; th uic brown fos jumps oger the aay do. hello, worldl type on your nees practice makes perfect. a sad ld asks da`
- +音+デコーダー+言語モデル: `asdf hkl; fufu didk slsp apap th uic brown fox jumps over the aay do. hello, world. thpe on your nees practice makes perfect. a sad ld asks da`

記録ファイル: synthetic-1-knee.json, synthetic-2-desk.json, synthetic-3-knee.json, synthetic-4-knee-heldout.json
