import CoreGraphics

/// 計算用の Vec2 と、画面描画用の CGPoint / CGSize を行き来するための変換。
/// (Core フォルダは Linux でもテストできるように CoreGraphics を import しないので、
///  変換はこのファイルにまとめています)
extension Vec2 {
    init(_ point: CGPoint) {
        self.init(Double(point.x), Double(point.y))
    }

    init(_ size: CGSize) {
        self.init(Double(size.width), Double(size.height))
    }

    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}
