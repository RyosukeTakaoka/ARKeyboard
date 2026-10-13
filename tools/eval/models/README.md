# tools/eval/models

`synthetic-LevelBTapModel.json` は、**合成データ**(乱数の種 11〜14)で学習したレベルB のモデルです。
評価ツールの動作確認(`python3 tools/eval/evaluate.py --synthetic --model tools/eval/models/synthetic-LevelBTapModel.json`)
のためのもので、実際の利用者の動きでは性能が出ない可能性が高いので、**アプリには同梱していません**。
自分の記録データで `tools/eval/train_levelb.py` を実行して作り直してください。
