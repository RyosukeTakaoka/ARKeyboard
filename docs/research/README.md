# 研究調査(docs/research)

調査日: 2026-10-13

「膝・机をキーボードにする」ために参考にした資料の要約です。1資料1ファイルで、
「入力・手法・出力・使ったデータ・評価指標と数値・限界」と出典 URL を書いています。

## 原文の取得状況(重要)

この調査を行ったクラウド環境では、ネットワーク設定により多くの論文サイト
(arxiv.org、tdcommons.org、dl.acm.org、bmva-archive.org.uk、winlab.rutgers.edu、
keithv.com、jungong.me、hbenko.com など)への接続が拒否されました。

| 資料 | 原文 | 要約の根拠 |
|---|---|---|
| [TouchInsight](touchinsight.md) | **未確認** | 検索エンジンが返した arXiv/ACM/プロジェクトページの抜粋(二次情報) |
| [Camera-Based Virtual Input(Google)](google-camera-based-virtual-input.md) | **未確認** | 検索結果に出た要旨の抜粋のみ |
| [Acustico](acustico.md) | **未確認** | 検索結果に出た要旨・本文の抜粋、Hackster.io の解説 |
| [VibKeyboard(Rutgers WINLAB ほか)](vibkeyboard.md) | **未確認** | 検索結果に出た要旨 |
| [EPFL 仮想キーボード(BMVC 2005)](epfl-bmvc2005.md) | **未確認** | 検索結果に出た要旨・抜粋 |
| [ソフトキーボードの統計的デコード](soft-keyboard-decoding.md) | Goodman ら: **確認済み(全文)** / VelociTap: **未確認** | Goodman らは microsoft.com の PDF を全文読んだ。VelociTap は検索結果の抜粋 |

### 追加調査(7-0、空間タッチモデルとフリック)

| 資料 | 原文 | 要約の根拠 |
|---|---|---|
| [当たり判定の動的リサイズ(Gunawardana ら)](key-target-resizing.md) | **確認済み(全文)** | microsoft.com の PDF |
| [Gboard の空間モデル](gboard-spatial-model.md) | **未確認** | 検索結果の要旨 |
| [SwiftKey のタッチ関連](swiftkey-touch.md) | **未確認**(技術論文なし) | 報道・公式投稿の抜粋 |
| [Apple の動的なヒット領域](apple-dynamic-hit-area.md) | **未確認**(内部仕様は非公開) | 特許を報じた記事の抜粋 |
| [日本語フリックの誤り補正・デコード](japanese-flick-decoding.md) | **未確認** | 検索結果の要旨。仮名コーパスと辞書のライセンスの調査を含む |

「未確認」の資料は、検索結果に書かれていたことだけを書き、書かれていない部分は
「不明」としています。数値は、検索結果の中で論文の要旨・本文の抜粋として示されたものです。
原文で確かめるまでは、引用時に注意してください。

まとめと「再現する/既存APIで代替/見送り」の判断は [feasibility.md](feasibility.md) にあります。
