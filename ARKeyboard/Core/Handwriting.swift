import Foundation

/// 手書きモードの設定(Tier3)
struct HandwritingConfig: Codable, Equatable {
    /// 書く手(もう一方の手は機能パッド: 空白・削除など。割り当てはフリックと共通)
    var hand: Chirality = .right
    /// ペンを下ろす: 親指の先と人差し指の先の距離がこれより近い(手の大きさ単位)
    var pinchDown: Double = 0.25
    /// ペンを上げる: これより離れる(下ろす値と離して、境目でペンがばたつかないようにする)
    var pinchUp: Double = 0.38
    /// ペンを上げてからこの時間(秒)たったら、1文字(ひとまとまり)書き終わったとみなして認識する
    var finishDelay: Double = 1.0
    /// 左右を反転する(カメラが手のひら側から見ているときなど、文字が鏡文字になるとき用)
    var mirror: Bool = false
    /// 認識する言語(Vision の言語コード)
    var language: String = "ja-JP"
    /// 認識の1位を自動で入力する(オフなら候補をタップして選ぶ)
    var autoInsert: Bool = true
}

/// 1画(ペンを下ろしてから上げるまで)。書く座標(x: 右、y: 上、単位は手の大きさ)
struct HandwritingStroke: Equatable {
    var points: [Vec2]
}

/// 人差し指と親指の「つまみ」をペンにして、軌跡を集める。
///
/// ## 向きの決め方(鏡文字にならないように)
/// 画像の上下左右は使いません。書き始めた瞬間の手の座標から:
/// - 上 = 手首 → 中指の付け根の向き(手の「前」)
/// - 右 = 上を、画面の上で時計回りに 90 度回した向き
/// カメラが手の甲側(上)から見ていれば、どの向きから撮っても左右は正しくなります。
/// 手のひら側(下)から見ていると鏡文字になるので、そのときは設定の「左右反転」を使います。
/// 背面カメラの映像は鏡像ではないので、通常は反転不要です(前面カメラは鏡像なので注意)。
///
/// 書いている間は手そのものが動くので、軌跡は「手の座標」ではなく、書き始めに固定した向きの座標で測ります。
final class HandwritingRecorder {
    var config = HandwritingConfig()

    /// 書き終わっていない画(書く座標)
    private(set) var strokes: [HandwritingStroke] = []
    /// 画面表示用の画(画像の座標)
    private(set) var displayStrokes: [[Vec2]] = []
    private(set) var isPenDown = false

    /// 書き始めに固定した向き(画像の座標)
    private var axes: (origin: Vec2, right: Vec2, up: Vec2, scale: Double)?
    private var penUpSince: Double?

    func clear() {
        strokes = []
        displayStrokes = []
        isPenDown = false
        axes = nil
        penUpSince = nil
    }

    /// 書く手の 1 フレーム分を処理する
    /// - Returns: 書き終わった(ペンを上げて finishDelay 秒たった)ときの画のまとまり
    func process(hand: HandObservation?, frame: HandFrame?, time: Double, minConfidence: Double) -> [HandwritingStroke]? {
        guard let hand, let frame,
              let thumb = hand.position(.thumbTip, minConfidence: minConfidence),
              let index = hand.position(.indexTip, minConfidence: minConfidence) else {
            return penUp(time: time)
        }
        let pinch = thumb.distance(to: index) / frame.scale
        let pen = (thumb + index) / 2
        if isPenDown ? pinch > config.pinchUp : pinch >= config.pinchDown {
            return penUp(time: time)
        }
        // ペンが下りている
        if axes == nil {
            let up = frame.forward
            var right = Vec2(-up.y, up.x)  // 画面の上で時計回りに 90 度(画像の座標は y が下向き)
            if config.mirror { right = right * -1 }
            axes = (pen, right, up, frame.scale)
        }
        guard let axes else { return nil }
        let d = pen - axes.origin
        let point = Vec2(d.dot(axes.right), d.dot(axes.up)) / axes.scale
        if !isPenDown {
            strokes.append(HandwritingStroke(points: []))
            displayStrokes.append([])
            isPenDown = true
        }
        strokes[strokes.count - 1].points.append(point)
        displayStrokes[displayStrokes.count - 1].append(pen)
        penUpSince = nil
        return nil
    }

    private func penUp(time: Double) -> [HandwritingStroke]? {
        if isPenDown {
            isPenDown = false
            penUpSince = time
        }
        guard let since = penUpSince, time - since >= config.finishDelay, !strokes.isEmpty else { return nil }
        let finished = strokes.filter { $0.points.count >= 2 }
        clear()
        return finished.isEmpty ? nil : finished
    }

    /// 画を白地に黒の画像(グレースケール、1画素 1 バイト、上の行から)にする。文字認識に渡すため。
    /// 画の範囲を、縦横比を保って余白付きで size × size に収める
    static func rasterize(_ strokes: [HandwritingStroke], size: Int = 160, lineWidth: Double = 7) -> [UInt8] {
        var pixels = [UInt8](repeating: 255, count: size * size)
        let points = strokes.flatMap(\.points)
        guard let first = points.first else { return pixels }
        var minP = first, maxP = first
        for p in points {
            minP = Vec2(min(minP.x, p.x), min(minP.y, p.y))
            maxP = Vec2(max(maxP.x, p.x), max(maxP.y, p.y))
        }
        let extent = max(maxP.x - minP.x, maxP.y - minP.y, 1e-6)
        let usable = Double(size) * 0.7
        let scale = usable / extent
        let center = (minP + maxP) / 2
        // 書く座標(y が上)→ 画像(y が下)
        func pixel(_ p: Vec2) -> Vec2 {
            Vec2(Double(size) / 2 + (p.x - center.x) * scale, Double(size) / 2 - (p.y - center.y) * scale)
        }
        let radius = lineWidth / 2
        func stamp(_ c: Vec2) {
            let r = Int(radius.rounded(.up))
            for y in max(0, Int(c.y) - r)...min(size - 1, Int(c.y) + r) {
                for x in max(0, Int(c.x) - r)...min(size - 1, Int(c.x) + r)
                where (Vec2(Double(x), Double(y)) - c).length <= radius {
                    pixels[y * size + x] = 0
                }
            }
        }
        for stroke in strokes {
            let ps = stroke.points.map(pixel)
            guard let start = ps.first else { continue }
            stamp(start)
            for (a, b) in zip(ps, ps.dropFirst()) {
                let steps = max(1, Int((b - a).length * 2))
                for i in 1...steps { stamp(Vec2.lerp(a, b, Double(i) / Double(steps))) }
            }
        }
        return pixels
    }
}
