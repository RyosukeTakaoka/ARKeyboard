import Foundation

/// LiDAR の深度マップ(各画素の「カメラからの距離」、単位はメートル)。
///
/// ARKit の sceneDepth は、カメラ画像と同じく **センサーの向き(横長)** で届きます(例: 256x192)。
/// 一方、このアプリの座標は「縦向きに起こした画像」(Vision に `.right` を指定した後の向き)です。
/// そのため、深さを読むときに向きを変換します。
///
/// ## `.right` の向きの変換
/// `.right` は「表示するには時計回りに 90 度回す画像」という意味でした(HandPoseDetector 参照)。
/// 縦向き画像の正規化座標 (ox, oy)(原点は左上、0〜1)と、横長のバッファの正規化座標 (bx, by) の関係は:
/// ```
///   bx = oy        (縦向き画像の「上下」が、バッファの「左右」)
///   by = 1 − ox    (縦向き画像の「左右」が、バッファの「下上」)
/// ```
/// 確認: バッファの1行目(by = 0)は、縦向きで見ると右端(ox = 1)。時計回りに 90 度回すと、
///       左上の角が右上に来るので合っています。
struct DepthMap: Equatable {
    /// バッファの幅と高さ(画素数、横長のまま)
    let width: Int
    let height: Int
    /// 深さ(メートル)。1行目の左から右、2行目…の順に並んだ配列
    let values: [Float]

    init(width: Int, height: Int, values: [Float]) {
        self.width = width
        self.height = height
        self.values = values
    }

    /// 縦向き画像の正規化座標(原点左上、0〜1)の点の深さ。読めなければ nil。
    func depth(atOrientedNormalized point: Vec2) -> Double? {
        let bx = point.y
        let by = 1 - point.x
        let x = Int((bx * Double(width)).rounded(.down))
        let y = Int((by * Double(height)).rounded(.down))
        return depth(x: x, y: y)
    }

    /// 周り 3x3 画素の深さの中央値(LiDAR は1画素ごとのノイズが大きいため)
    func medianDepth(atOrientedNormalized point: Vec2) -> Double? {
        let bx = point.y
        let by = 1 - point.x
        let cx = Int((bx * Double(width)).rounded(.down))
        let cy = Int((by * Double(height)).rounded(.down))
        var samples: [Double] = []
        for dy in -1...1 {
            for dx in -1...1 {
                if let d = depth(x: cx + dx, y: cy + dy) { samples.append(d) }
            }
        }
        return Self.median(samples)
    }

    private func depth(x: Int, y: Int) -> Double? {
        guard x >= 0, x < width, y >= 0, y < height, values.count == width * height else { return nil }
        let value = Double(values[y * width + x])
        // 0 や NaN(測れなかった画素)は使わない
        guard value.isFinite, value > 0 else { return nil }
        return value
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
}

/// 深度を使った「指が面に触れているか」の計算
enum DepthAssist {
    /// 指先の深さ − 手のひらの深さ(メートル)。
    ///
    /// - 指先が面に触れているとき、指先は手のひらより「奥」(カメラから遠い)にあるので値は大きい。
    /// - 指を持ち上げると、指先がカメラに近づくので値は小さくなる。
    /// - 手のひらとの「差」にしているので、膝ごと上下に動いても値はあまり変わらない。
    static func relativeTipDepth(hand: HandObservation, finger: Finger, imageSize: Vec2,
                                 depthMap: DepthMap, minConfidence: Double) -> Double? {
        func normalized(_ p: Vec2) -> Vec2 { Vec2(p.x / imageSize.x, p.y / imageSize.y) }

        guard let tip = hand.position(Joint.tip(of: finger), minConfidence: minConfidence),
              let dip = hand.position(Joint.dip(of: finger), minConfidence: minConfidence) else { return nil }
        // 指先ぴったりの点は、深度の粗い画素では背景と混ざりやすいので、少し内側(DIP寄り)を読む
        let fingerPoint = Vec2.lerp(dip, tip, 0.7)
        guard let tipDepth = depthMap.medianDepth(atOrientedNormalized: normalized(fingerPoint)) else { return nil }

        let palmJoints: [Joint] = [.wrist, .indexMCP, .middleMCP, .ringMCP, .littleMCP]
        let palmDepths = palmJoints
            .compactMap { hand.position($0, minConfidence: minConfidence) }
            .compactMap { depthMap.medianDepth(atOrientedNormalized: normalized($0)) }
        guard let palmDepth = DepthMap.median(palmDepths) else { return nil }
        return tipDepth - palmDepth
    }

    /// 指先が「面に触れていたときの高さ」から、どれだけ持ち上がっているか(メートル、正 = 持ち上がっている)
    static func heightAboveRest(current: Double, rest: Double) -> Double {
        rest - current
    }
}
