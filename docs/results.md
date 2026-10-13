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
| synthetic-1-knee.json | ルールのみ(カメラ) | 74.6% | 100.0% | 84.0% | 40.7% | 27.0 | right-index:8, thumb:4, left-index:4 |
| synthetic-1-knee.json | +音(二重条件) | 100.0% | 98.0% | 94.6% | 7.3% | 19.7 | left-index:3, right-index:3, left-middle:1 |
| synthetic-1-knee.json | +音+デコーダー(位置と指のみ) | 100.0% | 98.0% | 95.2% | 6.7% | 19.7 | left-index:3, right-index:2, left-middle:1 |
| synthetic-1-knee.json | +音+デコーダー+言語モデル | 100.0% | 98.0% | 98.6% | 3.3% | 19.7 | left-middle:1, right-index:1 |
| synthetic-1-knee.json | +音+デコーダー+言語モデル+個人適応 | 100.0% | 98.0% | 98.6% | 3.3% | 19.7 | left-middle:1, right-index:1 |
| synthetic-1-knee.json | +音+デコーダー+言語モデル+個人適応+単語デコード | 100.0% | 98.0% | 98.0% | 7.3% | 19.7 | right-index:2, left-middle:1 |
| synthetic-1-knee.json | +音+デコーダー+言語モデル+個人適応+レベルB | 99.3% | 100.0% | 93.3% | 7.3% | 20.3 | right-little:3, right-index:2, right-middle:2 |
| synthetic-2-desk.json | ルールのみ(カメラ) | 74.7% | 98.7% | 84.5% | 36.0% | 26.8 | right-index:6, thumb:4, left-middle:3 |
| synthetic-2-desk.json | +音(二重条件) | 99.3% | 94.7% | 97.9% | 8.0% | 19.3 | left-middle:1, right-index:1, right-ring:1 |
| synthetic-2-desk.json | +音+デコーダー(位置と指のみ) | 99.3% | 94.7% | 97.9% | 8.0% | 19.3 | left-middle:1, right-index:1, right-ring:1 |
| synthetic-2-desk.json | +音+デコーダー+言語モデル | 99.3% | 94.7% | 97.2% | 8.7% | 19.3 | right-index:2, left-middle:1, right-little:1 |
| synthetic-2-desk.json | +音+デコーダー+言語モデル+個人適応 | 99.3% | 94.7% | 96.5% | 9.3% | 19.3 | right-index:2, left-middle:1, right-little:1 |
| synthetic-2-desk.json | +音+デコーダー+言語モデル+個人適応+単語デコード | 99.3% | 94.7% | 97.2% | 10.0% | 19.3 | right-index:2, left-middle:1, right-little:1 |
| synthetic-2-desk.json | +音+デコーダー+言語モデル+個人適応+レベルB | 99.3% | 96.7% | 95.9% | 7.3% | 19.7 | left-middle:3, right-index:2, right-little:1 |
| synthetic-3-knee.json | ルールのみ(カメラ) | 74.6% | 100.0% | 82.7% | 40.0% | 27.0 | right-index:8, left-middle:4, thumb:4 |
| synthetic-3-knee.json | +音(二重条件) | 99.3% | 92.0% | 97.1% | 11.3% | 18.7 | right-ring:1, right-index:1, left-little:1 |
| synthetic-3-knee.json | +音+デコーダー(位置と指のみ) | 99.3% | 92.0% | 96.4% | 12.0% | 18.7 | right-index:2, right-ring:1, left-little:1 |
| synthetic-3-knee.json | +音+デコーダー+言語モデル | 99.3% | 92.0% | 96.4% | 10.7% | 18.7 | right-ring:2, left-middle:1, right-index:1 |
| synthetic-3-knee.json | +音+デコーダー+言語モデル+個人適応 | 99.3% | 92.0% | 95.7% | 11.3% | 18.7 | right-ring:2, right-index:2, left-middle:1 |
| synthetic-3-knee.json | +音+デコーダー+言語モデル+個人適応+単語デコード | 99.3% | 92.0% | 95.7% | 11.3% | 18.7 | right-ring:2, right-index:2, left-middle:1 |
| synthetic-3-knee.json | +音+デコーダー+言語モデル+個人適応+レベルB | 100.0% | 100.0% | 98.0% | 2.0% | 20.1 | right-little:1, right-index:1, left-index:1 |
| synthetic-5-knee-bias.json | ルールのみ(カメラ) | 65.6% | 100.0% | 61.2% | 64.1% | 30.5 | right-index:103, left-index:83, thumb:82 |
| synthetic-5-knee-bias.json | +音(二重条件) | 97.5% | 95.5% | 88.8% | 15.9% | 19.6 | left-index:48, right-index:30, left-ring:9 |
| synthetic-5-knee-bias.json | +音+デコーダー(位置と指のみ) | 97.5% | 95.5% | 88.9% | 15.8% | 19.6 | left-index:45, right-index:32, left-ring:9 |
| synthetic-5-knee-bias.json | +音+デコーダー+言語モデル | 97.5% | 95.5% | 94.2% | 10.8% | 19.6 | right-index:22, left-index:19, left-middle:7 |
| synthetic-5-knee-bias.json | +音+デコーダー+言語モデル+個人適応 | 97.5% | 95.5% | 96.3% | 8.8% | 19.6 | right-index:12, left-index:10, left-ring:6 |
| synthetic-5-knee-bias.json | +音+デコーダー+言語モデル+個人適応+単語デコード | 97.5% | 95.5% | 96.3% | 8.3% | 19.6 | right-index:12, left-index:10, left-ring:6 |
| synthetic-5-knee-bias.json | +音+デコーダー+言語モデル+個人適応+レベルB | 97.5% | 98.9% | 96.6% | 5.7% | 20.3 | right-index:19, left-index:8, right-ring:4 |
| synthetic-4-knee-heldout.json | ルールのみ(カメラ) | 68.7% | 100.0% | 86.3% | 51.9% | 29.2 | right-index:13, left-index:12, thumb:10 |
| synthetic-4-knee-heldout.json | +音(二重条件) | 98.6% | 94.8% | 96.2% | 9.9% | 19.3 | left-index:6, left-middle:3, right-ring:2 |
| synthetic-4-knee-heldout.json | +音+デコーダー(位置と指のみ) | 98.6% | 94.8% | 96.5% | 9.6% | 19.3 | left-index:5, left-middle:3, right-ring:2 |
| synthetic-4-knee-heldout.json | +音+デコーダー+言語モデル | 98.6% | 94.8% | 98.6% | 7.7% | 19.3 | left-index:4, right-index:1 |
| synthetic-4-knee-heldout.json | +音+デコーダー+言語モデル+個人適応 | 98.6% | 94.8% | 98.3% | 8.0% | 19.3 | left-index:4, left-middle:1, right-index:1 |
| synthetic-4-knee-heldout.json | +音+デコーダー+言語モデル+個人適応+単語デコード | 98.6% | 94.8% | 98.6% | 8.0% | 19.3 | left-index:3, left-middle:1, right-index:1 |
| synthetic-4-knee-heldout.json | +音+デコーダー+言語モデル+個人適応+レベルB | 97.8% | 97.5% | 96.6% | 7.7% | 20.1 | right-index:5, left-index:5, left-ring:1 |

## 位置のぶれへの強さ(人工的なぶれを加えた場合)

関節点に、手の大きさに対する標準偏差でガウス雑音を加えて再生した結果(最初の記録のみ)。

| 組み合わせ | ぶれ(手の大きさ比) | 適合率 | 再現率 | キー正解率 | CER |
|---|---|---|---|---|---|
| ルールのみ(カメラ) | 0.0 | 74.6% | 100.0% | 84.0% | 40.7% |
| ルールのみ(カメラ) | 0.01 | 71.1% | 100.0% | 86.0% | 45.3% |
| ルールのみ(カメラ) | 0.02 | 33.0% | 100.0% | 32.7% | 212.7% |
| ルールのみ(カメラ) | 0.04 | 10.2% | 100.0% | 6.7% | 896.7% |
| +音+デコーダー+言語モデル | 0.0 | 100.0% | 98.0% | 98.6% | 3.3% |
| +音+デコーダー+言語モデル | 0.01 | 99.3% | 97.3% | 98.6% | 4.7% |
| +音+デコーダー+言語モデル | 0.02 | 73.2% | 96.7% | 66.9% | 52.7% |
| +音+デコーダー+言語モデル | 0.04 | 31.1% | 98.0% | 15.6% | 250.0% |

## 言語モデルの重み w の比較(最後の記録)

| w | キー正解率 | CER |
|---|---|---|
| 0.0 | 96.5% | 9.6% |
| 0.3 | 98.8% | 7.4% |
| 0.5 | 98.6% | 7.7% |
| 0.7 | 98.3% | 8.2% |
| 1.0 | 96.8% | 9.3% |
| 1.5 | 94.5% | 11.3% |

## 入力された文字列の例(最初の記録)

- 目標: `asdf jkl; fjfj dkdk sls; a;a; the quick brown fox jumps over the lazy dog. hello, world. type on your knees practice makes perfect. a sad lad asks dad`
- ルールのみ(カメラ): `asddff  jkl; fjfj dkdk ssls; a;a; tfhed qaujikdk grfolwsh fllx jujjp;s olfedrf tfhed lazyj dolg. hedllol, wsolrfld. tfyjp;ed olj ujolujrf  knededs p;rfactfikced jakeds p;edfffedctf. aa sad lad asks dad`
- +音(二重条件): `asdf jkl; fjfj dkdk sls; a;a; the quidk grown flx jups ofer the lazy dog. helo, world. type oj uour knees practice jakes peffect. a sad lad asksdad`
- +音+デコーダー(位置と指のみ): `asdf jkl; fjfj dkdk sls; a;a; the quidk grown flx jups ofer the lazy dog. helo, world. type on uour knees practice jakes peffect. a sad lad asksdad`
- +音+デコーダー+言語モデル: `asef jkl; fufj dkdk sls; a;a; the quick brown fox jups over the lazy dog. helo, world. type on your knees practice makes perfect. a sad lad asksdad`
- +音+デコーダー+言語モデル+個人適応: `asef jkl; fufj dkdk sls; a;a; the quick brown fox jups over the lazy dog. helo, world. type on your knees practice makes perfect. a sad lad asksdad`
- +音+デコーダー+言語モデル+個人適応+単語デコード: `asef mil; futu didk sls; a;a; the quick brown fox jups over the lazy dog. helo, world. type on your knees practice makes peffect. a sad lad asksdad`
- +音+デコーダー+言語モデル+個人適応+レベルB: `asef jkl; fufj didi wosp apap the quick brown fox jumps over the lazy dog. hello, world. type on your  knees practice nakes perfect. a sad lad asks dad`

記録ファイル: synthetic-1-knee.json, synthetic-2-desk.json, synthetic-3-knee.json, synthetic-5-knee-bias.json, synthetic-4-knee-heldout.json
