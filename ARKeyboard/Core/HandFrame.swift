import Foundation

/// 手に貼り付けた「手の座標系」。
///
/// ## なぜ手の座標系が必要か
/// カメラの置き方(傾き・回転・距離)は毎回変わります。画像の「上」がキーボードの「奥」とは限りません。
/// そこで、画像の上下左右ではなく **手そのものを基準にした座標系** でキーの位置を表します。
/// こうすると、カメラを回転させたり手を斜めに置いたりしても、キー配置は手の向きについてきます。
///
/// ## 軸の決め方
/// ```
///              中指の付け根 (middleMCP)
///                  ▲
///                  │  forward(前)= 手首 → 中指の付け根 の向き
///                  │
///   小指側 ◀───── 手首 (wrist) ─────▶ 親指側
///                       thumbward(横)= forward に直交し、親指(人差し指)側を向く向き
/// ```
/// - 原点: 手首
/// - y 軸(forward): 手首 → 中指の付け根。キーボードでは「奥の段(Q W E…)」の向き。
/// - x 軸(thumbward): forward に直交する2つの向きのうち、**人差し指の付け根がある側**。
///   左右どちらに回すかを「人差し指側かどうか」で決めるので、画像が鏡像でも、
///   カメラが回転していても、必ず親指側が + になります。
/// - 単位: 手首〜中指の付け根の長さを 1 とする(「手の大きさ」単位)。
///   カメラに近づいて手が大きく映っても、数値が変わらないようにするためです。
///
/// 左手では「親指側 = キーボードの右」、右手では「親指側 = キーボードの左」になる点に注意。
struct HandFrame: Codable, Equatable {
    /// 原点(画像のピクセル座標)= 手首の位置
    var origin: Vec2
    /// 前向きの単位ベクトル(画像のピクセル座標系での向き)
    var forward: Vec2
    /// 横向き(親指側)の単位ベクトル
    var thumbward: Vec2
    /// 1「手の大きさ単位」が何ピクセルか(= 手首〜中指の付け根の長さ)
    var scale: Double

    init(origin: Vec2, forward: Vec2, thumbward: Vec2, scale: Double) {
        self.origin = origin
        self.forward = forward
        self.thumbward = thumbward
        self.scale = scale
    }

    /// 手の関節点から座標系を作ります。必要な点が無い(信頼度が低い)ときは nil。
    init?(hand: HandObservation, minConfidence: Double) {
        guard let wrist = hand.position(.wrist, minConfidence: minConfidence),
              let middleMCP = hand.position(.middleMCP, minConfidence: minConfidence) else {
            return nil
        }
        let forwardVector = middleMCP - wrist
        let length = forwardVector.length
        // 長さが極端に短い = 手が横から見えている等で向きが決められない
        guard length > 4, let forward = forwardVector.normalized else { return nil }

        // 「親指側」を知るための横向きのヒント。手のひらの幅方向(小指の付け根→人差し指の付け根)を使う。
        let index = hand.position(.indexMCP, minConfidence: minConfidence)
        let little = hand.position(.littleMCP, minConfidence: minConfidence)
        let sideHint: Vec2
        if let index, let little {
            sideHint = index - little
        } else if let index {
            sideHint = index - middleMCP
        } else if let little {
            sideHint = middleMCP - little
        } else {
            return nil
        }

        // forward を90度回したベクトルは、親指側か小指側のどちらか。
        // 内積が負なら小指側を向いているので、反転して親指側にそろえる。
        var thumbward = forward.perpendicular
        if thumbward.dot(sideHint) < 0 {
            thumbward = -thumbward
        }
        self.init(origin: wrist, forward: forward, thumbward: thumbward, scale: length)
    }

    /// 画像のピクセル座標 → 手の座標(x: 親指側+, y: 前+、単位は手の大きさ)
    func toLocal(_ imagePoint: Vec2) -> Vec2 {
        let d = imagePoint - origin
        // 各軸の単位ベクトルとの内積 =「その軸の向きにどれだけ進んでいるか」
        return Vec2(d.dot(thumbward) / scale, d.dot(forward) / scale)
    }

    /// 手の座標 → 画像のピクセル座標(toLocal の逆変換)
    func toImage(_ localPoint: Vec2) -> Vec2 {
        origin + thumbward * (localPoint.x * scale) + forward * (localPoint.y * scale)
    }

    /// 前フレームの座標系を、新しい座標系に少しだけ近づけたもの(手ぶれを抑える「平滑化」)。
    /// - Parameter alpha: 0〜1。1 なら新しい値そのまま、小さいほどゆっくり追従する(なめらかだが遅れる)。
    func smoothed(toward new: HandFrame, alpha: Double) -> HandFrame {
        let a = min(max(alpha, 0), 1)
        let origin = Vec2.lerp(self.origin, new.origin, a)
        let forward = Vec2.lerp(self.forward, new.forward, a).normalized ?? new.forward
        // 横向きは forward に直交するように作り直し、向き(親指側)は新しい値に合わせる
        var thumbward = forward.perpendicular
        if thumbward.dot(new.thumbward) < 0 { thumbward = -thumbward }
        let scale = self.scale + (new.scale - self.scale) * a
        return HandFrame(origin: origin, forward: forward, thumbward: thumbward, scale: scale)
    }

    /// 画像上で見たときの「回り方」。forward から thumbward へ回る向きの外積の符号。
    /// 手のひらを下にした手を上から(鏡像なしで)撮ると、左手は +1、右手は −1 になります。
    /// Vision が左右を判定できなかったときの推定に使います。
    var handedness: Chirality {
        forward.cross(thumbward) > 0 ? .left : .right
    }
}
