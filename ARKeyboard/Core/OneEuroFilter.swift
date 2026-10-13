import Foundation

/// One Euro フィルター(ぶれ除去)。Casiez, Roussel, Vogel「1€ Filter」(CHI 2012) の方法。
///
/// ## なぜ必要か
/// カメラで推定した関節点は、指を止めていても毎フレーム少し震えます。
/// 震えを消すために強く平均すると、今度は速い動き(フリック)に遅れて付いていくようになります。
/// One Euro フィルターは「遅いときは強くなめらかに、速いときは弱く(遅れを少なく)」と、
/// 動きの速さに応じてなめらかさを自動で変えます。
///
/// ## 計算
/// 1. 速さ(位置の変化 ÷ 時間)を、遮断周波数 dCutoff の低域通過フィルターでなめらかにする
/// 2. 位置の遮断周波数を cutoff = minCutoff + beta × 速さ にする(速いほど高い = 追従が速い)
/// 3. 位置を、その遮断周波数の低域通過フィルター(指数移動平均)でなめらかにする
///    指数移動平均の係数 α = 1 / (1 + 1 / (2π × cutoff × dt))
struct OneEuroFilter2 {
    /// 止まっているときの遮断周波数(Hz)。小さいほど震えが消えるが、動き出しに遅れる
    var minCutoff: Double
    /// 速さに応じて遮断周波数を上げる割合(手の大きさ単位/秒あたり)
    var beta: Double
    /// 速さをなめらかにする遮断周波数(Hz)
    var dCutoff: Double = 1.0

    private var last: Vec2?
    private var lastDerivative = Vec2.zero
    private var lastTime: Double?

    init(minCutoff: Double, beta: Double, dCutoff: Double = 1.0) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.dCutoff = dCutoff
    }

    private static func alpha(cutoff: Double, dt: Double) -> Double {
        let tau = 1 / (2 * Double.pi * max(cutoff, 1e-6))
        return 1 / (1 + tau / max(dt, 1e-6))
    }

    mutating func reset() {
        last = nil
        lastTime = nil
        lastDerivative = .zero
    }

    /// 新しい値を入れて、なめらかにした値を返す
    mutating func filter(_ value: Vec2, time: Double) -> Vec2 {
        guard let previous = last, let previousTime = lastTime, time > previousTime else {
            last = value
            lastTime = time
            lastDerivative = .zero
            return value
        }
        let dt = time - previousTime
        let derivative = (value - previous) / dt
        let aD = Self.alpha(cutoff: dCutoff, dt: dt)
        lastDerivative = lastDerivative + (derivative - lastDerivative) * aD
        let cutoff = minCutoff + beta * lastDerivative.length
        let a = Self.alpha(cutoff: cutoff, dt: dt)
        let result = previous + (value - previous) * a
        last = result
        lastTime = time
        return result
    }
}
