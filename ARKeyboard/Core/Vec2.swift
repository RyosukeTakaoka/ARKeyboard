import Foundation

/// 2次元のベクトル(「点の位置」と「向き・移動量」の両方に使います)。
///
/// ## なぜ CGPoint ではなく自前の型を使うのか
/// - 足し算・引き算・内積などの計算をたくさん書くので、演算子を用意しておくと式が読みやすくなる。
/// - `Core` フォルダのコードは Foundation だけに依存させ、Mac や Linux で
///   `swift test` による単体テストができるようにしている(UIKit/CoreGraphics を使わない)。
/// 画面描画で CGPoint が必要なときは `Support/Vec2+CoreGraphics.swift` の変換を使います。
struct Vec2: Equatable, Hashable, Codable {
    var x: Double
    var y: Double

    init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    static let zero = Vec2(0, 0)

    // MARK: 演算子(ベクトル同士の足し算・引き算、数値との掛け算・割り算)

    static func + (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x + b.x, a.y + b.y) }
    static func - (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x - b.x, a.y - b.y) }
    static func * (a: Vec2, k: Double) -> Vec2 { Vec2(a.x * k, a.y * k) }
    static func * (k: Double, a: Vec2) -> Vec2 { Vec2(a.x * k, a.y * k) }
    static func / (a: Vec2, k: Double) -> Vec2 { Vec2(a.x / k, a.y / k) }
    static prefix func - (a: Vec2) -> Vec2 { Vec2(-a.x, -a.y) }
    static func += (a: inout Vec2, b: Vec2) { a = a + b }
    static func -= (a: inout Vec2, b: Vec2) { a = a - b }

    // MARK: よく使う計算

    /// 内積。「self を other の向きに投影した長さ × other の長さ」。
    /// other が長さ1(単位ベクトル)なら、「self が other の向きにどれだけ進んでいるか」になります。
    func dot(_ other: Vec2) -> Double { x * other.x + y * other.y }

    /// 2次元の外積(z成分だけ)。正負で「other が self から見て左右どちら側にあるか」が分かります。
    func cross(_ other: Vec2) -> Double { x * other.y - y * other.x }

    /// 長さ
    var length: Double { (x * x + y * y).squareRoot() }

    /// 長さ1にしたベクトル。長さがほぼ0のときは向きが決められないので nil。
    var normalized: Vec2? {
        let len = length
        guard len > 1e-9 else { return nil }
        return self / len
    }

    /// 90度回転したベクトル(x, y) → (-y, x)。
    /// 「ある向きに直交する向き」を作るときに使います。
    var perpendicular: Vec2 { Vec2(-y, x) }

    /// 2点間の距離
    func distance(to other: Vec2) -> Double { (self - other).length }

    /// a と b の間を t (0〜1) で内分した点。t=0 なら a、t=1 なら b。
    static func lerp(_ a: Vec2, _ b: Vec2, _ t: Double) -> Vec2 { a + (b - a) * t }

    /// 点の平均。空なら nil。
    static func average(_ points: [Vec2]) -> Vec2? {
        guard !points.isEmpty else { return nil }
        let sum = points.reduce(Vec2.zero, +)
        return sum / Double(points.count)
    }
}
