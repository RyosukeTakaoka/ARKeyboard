import Foundation

/// ホモグラフィー(射影変換): 斜めから撮った平面を、真上から見た平面に直す 3×3 の変換。
///
/// ## なぜ使うのか(机モード)
/// カメラが机を斜めから見ていると、奥のものは小さく、手前のものは大きく映ります(遠近法)。
/// そのままだと、奥の段のキーは小さく、手前の段のキーは大きく測られてしまいます。
/// 机の四隅を画面で指定すると、「画像の点 → 机の上の本当の位置(cm)」の対応が4つ分かるので、
/// そこからホモグラフィーを計算して、すべての関節点を「真上から見た机の座標」に直します。
///
/// 膝モードでは、膝は曲面なので平面の仮定が成り立たず、使いません(手の座標系の相対位置だけを使う)。
///
/// ## 計算
/// 点 (x, y) を (x', y') に移す式:
/// ```
///   x' = (h0 x + h1 y + h2) / (h6 x + h7 y + 1)
///   y' = (h3 x + h4 y + h5) / (h6 x + h7 y + 1)
/// ```
/// 未知数は h0〜h7 の 8 個。対応する点が 4 組あれば、式が 8 本できるので解けます(連立一次方程式)。
struct Homography: Codable, Equatable {
    /// 3×3 行列の 9 個の数(行ごと。最後は 1)
    var m: [Double]

    static let identity = Homography(m: [1, 0, 0, 0, 1, 0, 0, 0, 1])

    /// 4 組の対応点から作る(src[i] が dst[i] に移る)。点の並びが一直線に近いなど、解けないときは nil。
    init?(from src: [Vec2], to dst: [Vec2]) {
        guard src.count == 4, dst.count == 4 else { return nil }
        // 8×8 の連立方程式 A h = b を作る
        var a = [[Double]](repeating: [Double](repeating: 0, count: 8), count: 8)
        var b = [Double](repeating: 0, count: 8)
        for i in 0..<4 {
            let (x, y) = (src[i].x, src[i].y)
            let (u, v) = (dst[i].x, dst[i].y)
            a[2 * i] = [x, y, 1, 0, 0, 0, -u * x, -u * y]
            b[2 * i] = u
            a[2 * i + 1] = [0, 0, 0, x, y, 1, -v * x, -v * y]
            b[2 * i + 1] = v
        }
        guard let h = Self.solve(a, b) else { return nil }
        self.m = h + [1]
    }

    init(m: [Double]) {
        self.m = m
    }

    /// 点を変換する。無限遠に飛ぶ(分母が 0 に近い)ときは nil。
    func apply(_ p: Vec2) -> Vec2? {
        let w = m[6] * p.x + m[7] * p.y + m[8]
        guard abs(w) > 1e-12 else { return nil }
        return Vec2((m[0] * p.x + m[1] * p.y + m[2]) / w,
                    (m[3] * p.x + m[4] * p.y + m[5]) / w)
    }

    /// 逆の変換(真上から見た座標 → 画像の座標)
    var inverse: Homography? {
        let (a, b, c, d, e, f, g, h, i) = (m[0], m[1], m[2], m[3], m[4], m[5], m[6], m[7], m[8])
        let det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
        guard abs(det) > 1e-12 else { return nil }
        let inv = [
            (e * i - f * h), -(b * i - c * h), (b * f - c * e),
            -(d * i - f * g), (a * i - c * g), -(a * f - c * d),
            (d * h - e * g), -(a * h - b * g), (a * e - b * d),
        ].map { $0 / det }
        // 最後の要素が 1 になるようにそろえる(同じ変換を表す)
        guard abs(inv[8]) > 1e-12 else { return Homography(m: inv) }
        return Homography(m: inv.map { $0 / inv[8] })
    }

    /// ガウスの消去法(部分ピボット選択つき)で A x = b を解く
    static func solve(_ aIn: [[Double]], _ bIn: [Double]) -> [Double]? {
        var a = aIn, b = bIn
        let n = b.count
        for col in 0..<n {
            // いちばん絶対値の大きい行を選んで入れ替える(誤差を小さくするため)
            guard let pivot = (col..<n).max(by: { abs(a[$0][col]) < abs(a[$1][col]) }),
                  abs(a[pivot][col]) > 1e-12 else { return nil }
            a.swapAt(col, pivot)
            b.swapAt(col, pivot)
            for row in (col + 1)..<n {
                let factor = a[row][col] / a[col][col]
                for k in col..<n { a[row][k] -= factor * a[col][k] }
                b[row] -= factor * b[col]
            }
        }
        var x = [Double](repeating: 0, count: n)
        for row in stride(from: n - 1, through: 0, by: -1) {
            var sum = b[row]
            for k in (row + 1)..<n { sum -= a[row][k] * x[k] }
            x[row] = sum / a[row][row]
        }
        return x
    }
}

/// 机の平面(四隅を画面で登録したもの)
struct DeskPlane: Codable, Equatable {
    /// 画像上の四隅(ピクセル)。順番: 奥の左, 奥の右, 手前の右, 手前の左(利用者から見て)
    var imageCorners: [Vec2]
    /// 机の登録した範囲の実際の大きさ(cm)。幅(左右)と奥行き(前後)
    var widthCm: Double
    var depthCm: Double

    /// 画像 → 真上から見た机の座標(cm。x は右、y は手前向き)
    var imageToPlane: Homography? {
        Homography(from: imageCorners, to: planeCorners)
    }

    /// 真上から見た机の座標 → 画像
    var planeToImage: Homography? {
        Homography(from: planeCorners, to: imageCorners)
    }

    private var planeCorners: [Vec2] {
        [Vec2(0, 0), Vec2(widthCm, 0), Vec2(widthCm, depthCm), Vec2(0, depthCm)]
    }

    /// 手の関節点をすべて机の座標に直す(信頼度はそのまま)
    func rectify(_ hand: HandObservation, using homography: Homography) -> HandObservation {
        var result = hand
        for (joint, point) in hand.joints {
            if let p = homography.apply(point.position) {
                result.joints[joint]?.position = p
            } else {
                result.joints[joint] = nil
            }
        }
        return result
    }
}
