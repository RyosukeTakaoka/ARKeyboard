このフォルダに、タップ推定レベルB の学習モデルを置きます(最初は空です)。

  python3 tools/eval/train_levelb.py recordings/*.json --out ARKeyboard/Resources/Model/

を実行すると、LevelBTapModel.json(と、coremltools があれば LevelBTapModel.mlmodel)ができます。
アプリをビルドし直し、設定 → タップ推定レベルB をオンにすると使われます。

※ 合成データで学習したモデルは同梱していません(実際の利用者の動きとは違うため)。
   自分の記録データで学習してください。
