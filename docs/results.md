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
| synthetic-1-knee.json | ルールのみ(カメラ) | 73.9% | 100.0% | 83.3% | 42.0% | 27.2 | right-index:8, thumb:5, left-index:4 |
| synthetic-1-knee.json | +音(二重条件) | 100.0% | 98.0% | 94.6% | 7.3% | 19.7 | left-index:3, right-index:3, left-middle:1 |
| synthetic-1-knee.json | +音+デコーダー(位置と指のみ) | 100.0% | 98.0% | 95.9% | 6.0% | 19.7 | left-index:3, left-middle:1, right-ring:1 |
| synthetic-1-knee.json | +音+デコーダー+言語モデル | 100.0% | 98.0% | 98.6% | 3.3% | 19.7 | left-middle:1, right-index:1 |
| synthetic-1-knee.json | +音+デコーダー+言語モデル+個人適応 | 100.0% | 98.0% | 98.6% | 3.3% | 19.7 | left-middle:1, right-index:1 |
| synthetic-1-knee.json | +音+デコーダー+言語モデル+個人適応+単語デコード | 100.0% | 98.0% | 98.6% | 7.3% | 19.7 | left-middle:1, right-index:1 |
| synthetic-2-desk.json | ルールのみ(カメラ) | 75.5% | 98.7% | 86.5% | 34.7% | 26.5 | right-index:5, thumb:4, left-ring:3 |
| synthetic-2-desk.json | +音(二重条件) | 99.3% | 94.7% | 97.9% | 8.0% | 19.3 | left-middle:1, right-ring:1, left-little:1 |
| synthetic-2-desk.json | +音+デコーダー(位置と指のみ) | 99.3% | 94.7% | 97.9% | 8.0% | 19.3 | left-middle:1, right-ring:1, left-little:1 |
| synthetic-2-desk.json | +音+デコーダー+言語モデル | 99.3% | 94.7% | 96.5% | 9.3% | 19.3 | right-index:2, left-middle:1, right-little:1 |
| synthetic-2-desk.json | +音+デコーダー+言語モデル+個人適応 | 99.3% | 94.7% | 96.5% | 9.3% | 19.3 | right-index:2, left-middle:1, right-little:1 |
| synthetic-2-desk.json | +音+デコーダー+言語モデル+個人適応+単語デコード | 99.3% | 94.7% | 97.2% | 10.0% | 19.3 | right-index:2, left-middle:1, right-little:1 |
| synthetic-3-knee.json | ルールのみ(カメラ) | 74.3% | 100.0% | 83.3% | 40.7% | 27.1 | right-index:7, left-middle:4, thumb:4 |
| synthetic-3-knee.json | +音(二重条件) | 99.3% | 92.0% | 97.1% | 11.3% | 18.7 | right-ring:1, right-index:1, left-little:1 |
| synthetic-3-knee.json | +音+デコーダー(位置と指のみ) | 99.3% | 92.0% | 96.4% | 12.0% | 18.7 | right-index:2, right-ring:1, left-little:1 |
| synthetic-3-knee.json | +音+デコーダー+言語モデル | 99.3% | 92.0% | 96.4% | 10.7% | 18.7 | right-ring:2, left-middle:1, right-index:1 |
| synthetic-3-knee.json | +音+デコーダー+言語モデル+個人適応 | 99.3% | 92.0% | 96.4% | 10.7% | 18.7 | right-ring:2, left-middle:1, right-index:1 |
| synthetic-3-knee.json | +音+デコーダー+言語モデル+個人適応+単語デコード | 99.3% | 92.0% | 96.4% | 11.3% | 18.7 | right-ring:2, left-middle:1, right-index:1 |
| synthetic-5-knee-bias.json | ルールのみ(カメラ) | 65.6% | 100.0% | 60.5% | 64.2% | 30.5 | right-index:103, left-index:88, thumb:85 |
| synthetic-5-knee-bias.json | +音(二重条件) | 97.4% | 95.5% | 88.7% | 16.0% | 19.6 | left-index:48, right-index:28, left-ring:9 |
| synthetic-5-knee-bias.json | +音+デコーダー(位置と指のみ) | 97.4% | 95.5% | 88.5% | 16.2% | 19.6 | left-index:46, right-index:32, left-ring:9 |
| synthetic-5-knee-bias.json | +音+デコーダー+言語モデル | 97.4% | 95.5% | 94.1% | 10.8% | 19.6 | right-index:21, left-index:20, left-middle:7 |
| synthetic-5-knee-bias.json | +音+デコーダー+言語モデル+個人適応 | 97.4% | 95.5% | 96.3% | 8.7% | 19.6 | right-index:12, left-index:10, thumb:6 |
| synthetic-5-knee-bias.json | +音+デコーダー+言語モデル+個人適応+単語デコード | 97.4% | 95.5% | 96.4% | 8.3% | 19.6 | right-index:12, left-index:9, thumb:6 |
| synthetic-4-knee-heldout.json | ルールのみ(カメラ) | 68.3% | 100.0% | 85.2% | 53.6% | 29.4 | left-index:15, right-index:14, thumb:10 |
| synthetic-4-knee-heldout.json | +音(二重条件) | 98.3% | 94.8% | 96.8% | 9.6% | 19.4 | left-index:4, left-middle:3, right-index:1 |
| synthetic-4-knee-heldout.json | +音+デコーダー(位置と指のみ) | 98.3% | 94.8% | 96.8% | 9.6% | 19.4 | left-index:4, left-middle:3, right-index:1 |
| synthetic-4-knee-heldout.json | +音+デコーダー+言語モデル | 98.3% | 94.8% | 98.3% | 8.2% | 19.4 | left-index:4, right-index:2 |
| synthetic-4-knee-heldout.json | +音+デコーダー+言語モデル+個人適応 | 98.3% | 94.8% | 98.6% | 8.0% | 19.4 | left-index:3, left-middle:1, right-index:1 |
| synthetic-4-knee-heldout.json | +音+デコーダー+言語モデル+個人適応+単語デコード | 98.3% | 94.8% | 98.6% | 8.0% | 19.4 | left-index:3, left-middle:1, right-index:1 |

## 位置のぶれへの強さ(人工的なぶれを加えた場合)

関節点に、手の大きさに対する標準偏差でガウス雑音を加えて再生した結果(最初の記録のみ)。

| 組み合わせ | ぶれ(手の大きさ比) | 適合率 | 再現率 | キー正解率 | CER |
|---|---|---|---|---|---|
| ルールのみ(カメラ) | 0.0 | 73.9% | 100.0% | 83.3% | 42.0% |
| ルールのみ(カメラ) | 0.01 | 70.4% | 100.0% | 82.0% | 47.3% |
| ルールのみ(カメラ) | 0.02 | 35.5% | 100.0% | 41.3% | 189.3% |
| ルールのみ(カメラ) | 0.04 | 10.0% | 100.0% | 6.7% | 906.7% |
| +音+デコーダー+言語モデル | 0.0 | 100.0% | 98.0% | 98.6% | 3.3% |
| +音+デコーダー+言語モデル | 0.01 | 99.3% | 98.0% | 98.0% | 4.7% |
| +音+デコーダー+言語モデル | 0.02 | 77.8% | 98.0% | 71.4% | 42.7% |
| +音+デコーダー+言語モデル | 0.04 | 31.8% | 88.7% | 6.8% | 214.7% |

## 言語モデルの重み w の比較(最後の記録)

| w | キー正解率 | CER |
|---|---|---|
| 0.0 | 96.8% | 9.6% |
| 0.3 | 98.6% | 8.0% |
| 0.5 | 98.3% | 8.2% |
| 0.7 | 98.3% | 8.0% |
| 1.0 | 97.4% | 9.1% |
| 1.5 | 93.9% | 12.1% |

## 入力された文字列の例(最初の記録)

- 目標: `asdf jkl; fjfj dkdk sls; a;a; the quick brown fox jumps over the lazy dog. hello, world. type on your knees practice makes perfect. a sad lad asks dad`
- ルールのみ(カメラ): `asddff  jkl; fjfj dkdk ssls; a;a; tfhed qaujikdk grfolwsh fllx jujjp;ss olfedrf tfhed lazyj dolg. hedllol, wsolrfld. tfyjp;ed olj ujolujrf  knededs p;rfactfikced jakeds p;edfffedctf. a ssad lad asks daad`
- +音(二重条件): `asdf jkl; fjfj dkdk sls; a;a; the quidk grown flx jups ofer the lazy dog. helo, world. type oj uour knees practice jakes peffect. a sad lad asksdad`
- +音+デコーダー(位置と指のみ): `asdf jkl; fjfj dkdk sls; a;a; the quidk grown flx jups ofer the lazy dog. helo, world. type on your knees practice jakes peffect. a sad lad asksdad`
- +音+デコーダー+言語モデル: `asef jkl; fufj dkdk sls; a;a; the quick brown fox jups over the lazy dog. helo, world. type on your knees practice makes perfect. a sad lad asksdad`
- +音+デコーダー+言語モデル+個人適応: `asef jkl; fufj dkdk sls; a;a; the quick brown fox jups over the lazy dog. helo, world. type on your knees practice makes perfect. a sad lad asksdad`
- +音+デコーダー+言語モデル+個人適応+単語デコード: `asef mil; futu didk sls; a;a; the quick brown fox jups over the lazy dog. helo, world. type on your knees practice makes peffect. a sad lad asksdad`

記録ファイル: synthetic-1-knee.json, synthetic-2-desk.json, synthetic-3-knee.json, synthetic-5-knee-bias.json, synthetic-4-knee-heldout.json
