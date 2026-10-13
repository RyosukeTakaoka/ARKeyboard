import Foundation

/// 「画像のピクセル座標」⇄「画面(View)の座標」を変換します。
///
/// ## 座標系の全体像(このアプリで出てくる3種類)
///
/// 1. **Vision の正規化座標**
///    - 範囲は 0〜1(画像の幅・高さを 1 とした割合)。
///    - **原点が左下**で、y は上向きが正(数学のグラフと同じ向き)。
///    - x は「幅に対する割合」、y は「高さに対する割合」なので、縦長の画像では
///      x の 0.1 と y の 0.1 は実際の長さが違う(＝そのままでは距離や角度を計算できない)。
///
/// 2. **画像のピクセル座標**(このアプリの計算はすべてこれで行う)
///    - VisionHandTracker で、Vision の座標を次の式で変換しています:
///        x_px = x_vision × 画像の幅
///        y_px = (1 − y_vision) × 画像の高さ   ← 上下を反転して「原点を左上」にする
///    - 原点が左上、y は下向きが正(UIKit/SwiftUI と同じ向き)。
///    - x と y の単位がどちらも「ピクセル」なので、距離や角度を正しく計算できる。
///    - 「画像」は、カメラの向きを補正した後(縦向き)の画像です(詳しくは VisionHandTracker)。
///
/// 3. **画面(View)の座標**(ポイント単位)
///    - カメラのプレビューは `.resizeAspectFill`(縦横比を保って画面いっぱいに拡大し、はみ出しは切る)
///      で表示しているので、同じ計算で画像ピクセル → 画面ポイントに変換します。
///
/// ```
///  画像(720x1280) を 画面(393x852) に aspectFill すると:
///    scale = max(393/720, 852/1280) = 0.666
///    拡大後の画像 = 479.4 x 852 → 左右が (479.4-393)/2 = 43.2pt ずつはみ出す
///    画面の x = 画像の x × 0.666 − 43.2
/// ```
struct CoordinateConverter: Equatable {
    /// 画像のサイズ(ピクセル)
    var imageSize: Vec2
    /// 画面(View)のサイズ(ポイント)
    var viewSize: Vec2

    /// 画像 → 画面 の拡大率(aspectFill なので、縦と横の拡大率の「大きい方」)
    var scale: Double {
        guard imageSize.x > 0, imageSize.y > 0 else { return 1 }
        return max(viewSize.x / imageSize.x, viewSize.y / imageSize.y)
    }

    /// 拡大した画像を画面の中央に置いたときの、左上のずれ(はみ出した分はマイナスになる)
    var offset: Vec2 {
        let s = scale
        return Vec2((viewSize.x - imageSize.x * s) / 2, (viewSize.y - imageSize.y * s) / 2)
    }

    /// 画像のピクセル座標 → 画面の座標
    func viewPoint(fromImage p: Vec2) -> Vec2 {
        p * scale + offset
    }

    /// 画面の座標 → 画像のピクセル座標(逆変換)
    func imagePoint(fromView p: Vec2) -> Vec2 {
        (p - offset) / scale
    }

    /// 長さ(ピクセル)→ 長さ(ポイント)。向きを持たない「大きさ」の変換用。
    func viewLength(fromImage length: Double) -> Double {
        length * scale
    }
}
