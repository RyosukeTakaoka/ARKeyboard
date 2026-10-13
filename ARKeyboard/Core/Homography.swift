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

    /// 対応点から作る(src[i] が dst[i] に移る)。4 組ならぴったり、5 組以上なら最小二乗で一番合うものを求める。
    /// 点の並びが一直線に近いなど、解けないときは nil。
    ///
    /// ## 精度の工夫(正規化 DLT、Hartley 1997)
    /// 画像の座標(数百〜千ピクセル)と机の座標(数十 cm)をそのまま式に入れると、x·u のような項が
    /// 桁違いに大きくなり、計算の誤差が増えます。そこで先に、それぞれの点の集まりを
    /// 「重心が原点、原点からの平均距離が √2」になるように移動・拡大縮小(T)してから解き、
    /// 最後に元の座標に戻します: H = T_dst⁻¹ × H_正規化 × T_src
    init?(from src: [Vec2], to dst: [Vec2]) {
        guard src.count >= 4, src.count == dst.count,
              let ts = Self.normalization(src), let td = Self.normalization(dst) else { return nil }
        let ns = src.map { ts.apply($0)! }
        let nd = dst.map { td.apply($0)! }
        // 式 A h = b(1 組につき 2 本)。5 組以上なら、正規方程式 (AᵀA) h = Aᵀb で最小二乗
        var rows: [[Double]] = []
        var rhs: [Double] = []
        for (p, q) in zip(ns, nd) {
            rows.append([p.x, p.y, 1, 0, 0, 0, -q.x * p.x, -q.x * p.y]); rhs.append(q.x)
            rows.append([0, 0, 0, p.x, p.y, 1, -q.y * p.x, -q.y * p.y]); rhs.append(q.y)
        }
        var ata = [[Double]](repeating: [Double](repeating: 0, count: 8), count: 8)
        var atb = [Double](repeating: 0, count: 8)
        for (row, b) in zip(rows, rhs) {
            for i in 0..<8 {
                atb[i] += row[i] * b
                for j in 0..<8 { ata[i][j] += row[i] * row[j] }
            }
        }
        guard let h = Self.solve(ata, atb), let tdInverse = td.inverse else { return nil }
        let normalized = Homography(m: h + [1])
        let full = tdInverse.multiplied(by: normalized).multiplied(by: ts)
        guard abs(full.m[8]) > 1e-12 else { return nil }
        self.m = full.m.map { $0 / full.m[8] }
    }

    /// 点の集まりを「重心が原点、原点からの平均距離が √2」にする変換
    static func normalization(_ points: [Vec2]) -> Homography? {
        guard !points.isEmpty else { return nil }
        let centroid = points.reduce(Vec2.zero, +) / Double(points.count)
        let meanDistance = points.reduce(0.0) { $0 + ($1 - centroid).length } / Double(points.count)
        guard meanDistance > 1e-12 else { return nil }
        let k = 2.0.squareRoot() / meanDistance
        return Homography(m: [k, 0, -k * centroid.x, 0, k, -k * centroid.y, 0, 0, 1])
    }

    /// 行列の積(self × other: 先に other、次に self を当てる変換)
    func multiplied(by other: Homography) -> Homography {
        var r = [Double](repeating: 0, count: 9)
        for i in 0..<3 {
            for j in 0..<3 {
                var sum = 0.0
                for k in 0..<3 {
                    let a: Double = m[3 * i + k]
                    let b: Double = other.m[3 * k + j]
                    sum += a * b
                }
                r[3 * i + j] = sum
            }
        }
        return Homography(m: r)
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

/// 机の平面(四隅、または 3×3 の 9 点を登録したもの)
struct DeskPlane: Codable, Equatable {
    /// 画像上の四隅(ピクセル)。順番: 奥の左, 奥の右, 手前の右, 手前の左(利用者から見て)
    var imageCorners: [Vec2]
    /// 机の登録した範囲の実際の大きさ(cm)。幅(左右)と奥行き(前後)
    var widthCm: Double
    var depthCm: Double
    /// 9 点で登録したときの画像上の点(奥の行から、左→右の順に 3×3)。あれば四隅の代わりに最小二乗で使う
    var gridPoints: [Vec2]? = nil

    init(imageCorners: [Vec2], widthCm: Double, depthCm: Double) {
        self.imageCorners = imageCorners
        self.widthCm = widthCm
        self.depthCm = depthCm
    }

    /// 3×3 の 9 点から作る(四隅は 9 点の角を使う)
    init(gridPoints: [Vec2], widthCm: Double, depthCm: Double) {
        self.gridPoints = gridPoints
        self.imageCorners = gridPoints.count == 9 ? [gridPoints[0], gridPoints[2], gridPoints[8], gridPoints[6]] : []
        self.widthCm = widthCm
        self.depthCm = depthCm
    }

    /// 登録する点の名前(画面の案内用)
    static let cornerNames = ["奥の左", "奥の右", "手前の右", "手前の左"]
    static let gridNames = ["奥の左", "奥の中央", "奥の右", "中段の左", "真ん中", "中段の右", "手前の左", "手前の中央", "手前の右"]

    /// 画像 → 真上から見た机の座標(cm。x は右、y は手前向き)
    var imageToPlane: Homography? {
        Homography(from: imagePoints, to: planePoints)
    }

    /// 真上から見た机の座標 → 画像
    var planeToImage: Homography? {
        Homography(from: planePoints, to: imagePoints)
    }

    private var imagePoints: [Vec2] {
        if let gridPoints, gridPoints.count == 9 { return gridPoints }
        return imageCorners
    }

    private var planePoints: [Vec2] {
        if let gridPoints, gridPoints.count == 9 {
            return (0..<9).map { Vec2(Double($0 % 3) * widthCm / 2, Double($0 / 3) * depthCm / 2) }
        }
        return [Vec2(0, 0), Vec2(widthCm, 0), Vec2(widthCm, depthCm), Vec2(0, depthCm)]
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

/// 指先で机の点を押さえて登録する(画面をタップするより正確にするため)。
///
/// 指先(人差し指の先)が 0.8 秒ほぼ止まったら、その間の位置の平均を 1 点として記録します。
/// 平均すると、カメラの関節点の細かい震えが打ち消されます。記録したら、指先がいったん離れる
/// (moveAway ピクセル以上動く)まで次の点は記録しません(同じ場所を 2 回記録しないため)。
final class FingertipPointCapture {
    /// 止まっているとみなす、位置のばらつきの上限(ピクセル。平均からの最大の距離)
    var stillRadius: Double = 6
    /// 止まっていなければならない時間(秒)
    var holdDuration: Double = 0.8
    /// 次の点に移るために動かす距離(ピクセル)
    var moveAway: Double = 40

    private var samples: [(t: Double, p: Vec2)] = []
    private var lastCaptured: Vec2?
    /// 今の止まり具合(0〜1。画面の進み具合の表示用)
    private(set) var progress: Double = 0

    func reset() {
        samples = []
        lastCaptured = nil
        progress = 0
    }

    /// 1 フレーム分。点を記録したら、その位置(平均)を返す
    func process(fingertip: Vec2?, time: Double) -> Vec2? {
        guard let p = fingertip else {
            samples = []
            progress = 0
            return nil
        }
        if let last = lastCaptured {
            if p.distance(to: last) < moveAway { progress = 0; return nil }
            lastCaptured = nil
        }
        samples.append((time, p))
        samples.removeAll { $0.t < time - holdDuration - 0.1 }
        let mean = samples.reduce(Vec2.zero) { $0 + $1.p } / Double(samples.count)
        // ばらつきが大きければ、止まった時点からやり直す(最新の点の近くだけ残す)
        if samples.contains(where: { $0.p.distance(to: mean) > stillRadius }) {
            samples = [(time, p)]
            progress = 0
            return nil
        }
        let span = time - (samples.first?.t ?? time)
        progress = min(span / holdDuration, 1)
        guard span >= holdDuration else { return nil }
        samples = []
        progress = 0
        lastCaptured = mean
        return mean
    }
}
