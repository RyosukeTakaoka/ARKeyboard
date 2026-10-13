# Apple の動的なヒット領域(予測で当たり判定が広がる)

- 対象資料: 米国特許 8,232,973「Method, device, and graphical user interface providing word recommendations for text input」
  (Apple。関連特許 8,074,172)と、それを紹介した記事。
- 出典 URL:
  - https://appleinsider.com/articles/12/07/31/apple_granted_patent_for_predictive_text_input_ui
  - https://gizmodo.com/the-iphones-future-predictive-keyboard-makes-certain-ke-5930577
- **原文: 未確認**(特許の本文は読んでいない。記事の要旨は検索結果による二次情報)。
- **iOS の実際のキーボードの内部仕様は公開されておらず、確認できない**。

## 分かったこと(二次情報)
- 特許は、予測入力の仕組みに基づいて、**見た目のキーの大きさは変えずに、キーの実効的な(当たり判定の)領域を広げる**方法を扱う、と報じられている。
- 記事によって、例として挙げられたキーが違う(「ELEPHANT」の例で P とする記事と E とする記事がある)。

## このアプリでの扱い
- 指示どおり、Apple の内部の仕組みを再現するのではなく、
  **「事前確率(言語モデル)の変化で、実効的な当たり判定が広がる」**ことを、
  Gunawardana らの source-channel の形(key-target-resizing.md)で再現する。
- 当たり判定が消えてしまう問題を防ぐため、アンカー(キー中央は必ずそのキー)を入れる。
