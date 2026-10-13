# 評価結果(docs/results.md)

作成日: 2026-10-13(`python3 tools/eval/evaluate.py` で自動生成)

> ⚠️ **この表は合成データ(人工的に作った手の動き)による結果です。実際の利用者の性能ではありません。**
> 評価ツールが正しく動くことの確認と、「どの機能がどの種類の誤りに効くか」の見通しのためのものです。
> 実機の記録モードで集めたデータで `python3 tools/eval/evaluate.py recordings/*.json` を実行して、
> この表を置き換えてください。

合成データの作り方: `ARKeyboard/Core/SyntheticRecordingGenerator.swift`(狙いのずれ σ=0.25 キー、
(レベルB のモデルは、評価用とは別の乱数の種 11〜14 の合成データで学習したもの)
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
| synthetic-1-knee.json | ルールのみ(カメラ) | 74.3% | 100.0% | 84.0% | 40.7% | 27.1 | right-index:8, thumb:4, left-index:4 |
| synthetic-1-knee.json | +音(二重条件) | 100.0% | 98.0% | 94.6% | 7.3% | 19.7 | left-index:3, right-index:3, left-middle:1 |
| synthetic-1-knee.json | +音+デコーダー(位置と指のみ) | 100.0% | 98.0% | 94.6% | 7.3% | 19.7 | left-index:3, right-index:3, left-middle:1 |
| synthetic-1-knee.json | +音+デコーダー+言語モデル | 100.0% | 98.0% | 98.6% | 3.3% | 19.7 | left-middle:1, right-index:1 |
| synthetic-1-knee.json | +音+デコーダー+言語モデル+個人適応 | 100.0% | 98.0% | 98.6% | 3.3% | 19.7 | left-middle:1, right-index:1 |
| synthetic-1-knee.json | +音+デコーダー+言語モデル+個人適応+単語デコード | 100.0% | 98.0% | 98.6% | 7.3% | 19.7 | left-middle:1, right-index:1 |
| synthetic-1-knee.json | +音+デコーダー+言語モデル+個人適応+レベルB | 100.0% | 99.3% | 96.0% | 4.7% | 20.0 | right-little:3, right-index:2, left-middle:1 |
| synthetic-2-desk.json | ルールのみ(カメラ) | 75.1% | 98.7% | 85.8% | 34.0% | 26.6 | right-index:5, thumb:4, left-ring:3 |
| synthetic-2-desk.json | +音(二重条件) | 99.3% | 94.7% | 98.6% | 7.3% | 19.3 | right-ring:1, left-little:1 |
| synthetic-2-desk.json | +音+デコーダー(位置と指のみ) | 99.3% | 94.7% | 98.6% | 7.3% | 19.3 | right-ring:1, left-little:1 |
| synthetic-2-desk.json | +音+デコーダー+言語モデル | 99.3% | 94.7% | 96.5% | 9.3% | 19.3 | right-index:2, left-middle:1, right-little:1 |
| synthetic-2-desk.json | +音+デコーダー+言語モデル+個人適応 | 99.3% | 94.7% | 96.5% | 9.3% | 19.3 | right-index:2, left-middle:1, right-little:1 |
| synthetic-2-desk.json | +音+デコーダー+言語モデル+個人適応+単語デコード | 99.3% | 94.7% | 97.2% | 10.0% | 19.3 | right-index:2, left-middle:1, right-little:1 |
| synthetic-2-desk.json | +音+デコーダー+言語モデル+個人適応+レベルB | 99.3% | 97.3% | 96.6% | 6.7% | 19.9 | right-index:3, left-middle:1, right-little:1 |
| synthetic-3-knee.json | ルールのみ(カメラ) | 73.2% | 100.0% | 83.3% | 42.7% | 27.5 | right-index:8, thumb:4, left-middle:3 |
| synthetic-3-knee.json | +音(二重条件) | 99.3% | 92.0% | 96.4% | 12.0% | 18.7 | right-index:2, right-ring:1, left-little:1 |
| synthetic-3-knee.json | +音+デコーダー(位置と指のみ) | 99.3% | 92.0% | 96.4% | 12.0% | 18.7 | right-index:2, right-ring:1, left-little:1 |
| synthetic-3-knee.json | +音+デコーダー+言語モデル | 99.3% | 92.0% | 95.7% | 12.0% | 18.7 | right-ring:2, right-index:2, left-middle:1 |
| synthetic-3-knee.json | +音+デコーダー+言語モデル+個人適応 | 99.3% | 92.0% | 95.7% | 12.0% | 18.7 | right-ring:2, right-index:2, left-middle:1 |
| synthetic-3-knee.json | +音+デコーダー+言語モデル+個人適応+単語デコード | 99.3% | 92.0% | 95.7% | 11.3% | 18.7 | right-ring:2, right-index:2, left-middle:1 |
| synthetic-3-knee.json | +音+デコーダー+言語モデル+個人適応+レベルB | 99.3% | 100.0% | 94.7% | 6.0% | 20.3 | right-index:3, right-ring:2, left-middle:1 |
| synthetic-5-knee-bias.json | ルールのみ(カメラ) | 65.3% | 100.0% | 60.2% | 64.8% | 30.7 | right-index:109, left-index:85, thumb:84 |
| synthetic-5-knee-bias.json | +音(二重条件) | 97.5% | 95.6% | 88.7% | 15.9% | 19.6 | left-index:49, right-index:28, left-ring:10 |
| synthetic-5-knee-bias.json | +音+デコーダー(位置と指のみ) | 97.5% | 95.6% | 88.5% | 16.1% | 19.6 | left-index:47, right-index:32, left-ring:10 |
| synthetic-5-knee-bias.json | +音+デコーダー+言語モデル | 97.5% | 95.6% | 93.9% | 10.9% | 19.6 | right-index:22, left-index:19, left-middle:8 |
| synthetic-5-knee-bias.json | +音+デコーダー+言語モデル+個人適応 | 97.5% | 95.6% | 96.1% | 8.8% | 19.6 | right-index:13, left-index:10, thumb:6 |
| synthetic-5-knee-bias.json | +音+デコーダー+言語モデル+個人適応+単語デコード | 97.5% | 95.6% | 96.1% | 8.2% | 19.6 | right-index:13, left-index:10, thumb:6 |
| synthetic-5-knee-bias.json | +音+デコーダー+言語モデル+個人適応+レベルB | 97.7% | 98.6% | 96.0% | 6.1% | 20.2 | right-index:19, left-index:14, left-ring:4 |
| synthetic-4-knee-heldout.json | ルールのみ(カメラ) | 68.7% | 100.0% | 86.0% | 52.5% | 29.2 | right-index:14, left-index:12, thumb:10 |
| synthetic-4-knee-heldout.json | +音(二重条件) | 98.3% | 94.8% | 95.9% | 10.4% | 19.4 | left-index:7, right-ring:2, left-middle:2 |
| synthetic-4-knee-heldout.json | +音+デコーダー(位置と指のみ) | 98.3% | 94.8% | 96.5% | 9.9% | 19.4 | left-index:5, right-ring:2, left-middle:2 |
| synthetic-4-knee-heldout.json | +音+デコーダー+言語モデル | 98.3% | 94.8% | 98.3% | 8.2% | 19.4 | left-index:4, right-index:2 |
| synthetic-4-knee-heldout.json | +音+デコーダー+言語モデル+個人適応 | 98.3% | 94.8% | 98.6% | 8.0% | 19.4 | left-index:3, left-middle:1, right-index:1 |
| synthetic-4-knee-heldout.json | +音+デコーダー+言語モデル+個人適応+単語デコード | 98.3% | 94.8% | 98.6% | 8.2% | 19.4 | left-index:3, left-middle:1, right-index:1 |
| synthetic-4-knee-heldout.json | +音+デコーダー+言語モデル+個人適応+レベルB | 98.4% | 98.6% | 97.2% | 5.5% | 20.2 | right-index:5, left-index:4, thumb:1 |

## 位置のぶれへの強さ(人工的なぶれを加えた場合)

関節点に、手の大きさに対する標準偏差でガウス雑音を加えて再生した結果(最初の記録のみ)。

| 組み合わせ | ぶれ(手の大きさ比) | 適合率 | 再現率 | キー正解率 | CER |
|---|---|---|---|---|---|
| ルールのみ(カメラ) | 0.0 | 74.3% | 100.0% | 84.0% | 40.7% |
| ルールのみ(カメラ) | 0.01 | 71.8% | 100.0% | 83.3% | 45.3% |
| ルールのみ(カメラ) | 0.02 | 33.8% | 100.0% | 41.3% | 206.7% |
| ルールのみ(カメラ) | 0.04 | 10.2% | 100.0% | 8.0% | 889.3% |
| +音+デコーダー+言語モデル | 0.0 | 100.0% | 98.0% | 98.6% | 3.3% |
| +音+デコーダー+言語モデル | 0.01 | 99.3% | 98.0% | 98.0% | 4.7% |
| +音+デコーダー+言語モデル | 0.02 | 72.3% | 97.3% | 74.0% | 45.3% |
| +音+デコーダー+言語モデル | 0.04 | 30.0% | 98.7% | 8.1% | 260.0% |

## 言語モデルの重み w の比較(最後の記録)

| w | キー正解率 | CER |
|---|---|---|
| 0.0 | 96.5% | 9.9% |
| 0.3 | 98.6% | 8.0% |
| 0.5 | 98.3% | 8.2% |
| 0.7 | 98.0% | 8.5% |
| 1.0 | 95.4% | 10.7% |
| 1.5 | 94.2% | 11.8% |

## 入力された文字列の例(最初の記録)

- 目標: `asdf jkl; fjfj dkdk sls; a;a; the quick brown fox jumps over the lazy dog. hello, world. type on your knees practice makes perfect. a sad lad asks dad`
- ルールのみ(カメラ): `asddf  jkl; fjfj dkdk ssls; a;a; tfhed qaujikdk grfolwshn fllxx jujjp;s olfedrf tfhed lazyj dolg. hedllol, wsolrfld. tfyjp;ed olj ujolujrf  knededs p;rfactfikced jakeds p;edfffedctf. a sad lad asks daad`
- +音(二重条件): `asdf jkl; fjfj dkdk sls; a;a; the quidk grown flx jups ofer the lazy dog. helo, world. type oj uour knees practice jakes peffect. a sad lad asksdad`
- +音+デコーダー(位置と指のみ): `asdf jkl; fjfj dkdk sls; a;a; the quidk grown flx jups ofer the lazy dog. helo, world. type oj uour knees practice jakes peffect. a sad lad asksdad`
- +音+デコーダー+言語モデル: `asef jkl; fufj dkdk sls; a;a; the quick brown fox jups over the lazy dog. helo, world. type on your knees practice makes perfect. a sad lad asksdad`
- +音+デコーダー+言語モデル+個人適応: `asef jkl; fufj dkdk sls; a;a; the quick brown fox jups over the lazy dog. helo, world. type on your knees practice makes perfect. a sad lad asksdad`
- +音+デコーダー+言語モデル+個人適応+単語デコード: `asef mil; futu didk sls; a;a; the quick brown fox jups over the lazy dog. helo, world. type on your knees practice makes peffect. a sad lad asksdad`
- +音+デコーダー+言語モデル+個人適応+レベルB: `asef jkl; fufj dkdk slsp apap the quick brown fox jumps over the laz dog. hello, world. type on your knees practice nakes perfect. a sad lad asks dad`

記録ファイル: synthetic-1-knee.json, synthetic-2-desk.json, synthetic-3-knee.json, synthetic-5-knee-bias.json, synthetic-4-knee-heldout.json
