import Foundation

/// 机の登録方法ごとの「キーの位置の誤差」を、仮想のカメラで見積もる(評価用。アプリの動作には使わない)。
///
/// 仮想のカメラ: 机の手前の上 `height` cm から、机のほうへ `tilt` 度見下ろす(焦点距離 f ピクセル)。
/// 登録する点の画像上の位置に誤差を加えてホモグラフィーを作り、キーが並ぶ範囲の点を変換して、
/// 本当の机の位置とのずれ(mm)を測ります。
///
/// 誤差の想定(仮説。実機で測って置き換える):
/// - 画面タップ: 指で画面の角を狙う誤差 σ = tapNoisePx(画面のタップは指の幅でずれる)
/// - 指先: カメラの関節点の震え σ = keypointNoisePx を、止まっている間(holdFrames フレーム)平均する
///   + 指先の関節点と、実際に角に触れている位置のずれ σ = fingertipBiasCm(机の上で)
enum DeskAccuracySimulation {
    enum Method: String, CaseIterable {
        case tap4 = "画面タップ・四隅"
        case finger4 = "指先・四隅"
        case finger9 = "指先・9点"
    }

    struct Camera {
        var height = 40.0       // cm
        var tilt = 50.0         // 度(水平から見下ろす角度)
        var distance = 15.0     // カメラの真下から、登録する範囲の手前の辺までの距離(cm)
        var focal = 1400.0      // ピクセル
        var imageSize = Vec2(1080, 1920)

        /// 机の上の点(x: 右, y: 手前向き。原点は範囲の奥の左)→ 画像
        func project(_ p: Vec2, width: Double, depth: Double) -> Vec2 {
            // カメラ座標: カメラの真下を原点に、X 右、Y 奥へ、Z 上
            let X = p.x - width / 2
            let Y = distance + (depth - p.y)
            let Z = -height
            let t = tilt * Double.pi / 180
            // カメラの向き: 奥へ、水平から t 度下向き
            let forward = (0.0, cos(t), -sin(t))
            let up = (0.0, sin(t), cos(t))
            let zc = Y * forward.1 + Z * forward.2
            let yc = Y * up.1 + Z * up.2
            return Vec2(imageSize.x / 2 + focal * X / zc, imageSize.y / 2 - focal * yc / zc)
        }
    }

    struct Noise {
        var tapNoisePx = 10.0
        var keypointNoisePx = 4.0
        var holdFrames = 24.0
        var fingertipBiasCm = 0.2
    }

    /// - Returns: キーの位置の誤差(mm)の平均と 95 パーセンタイル
    static func run(method: Method, camera: Camera = Camera(), noise: Noise = Noise(), width: Double = 30, depth: Double = 15,
                    trials: Int = 500, seed: UInt64 = 1) -> (mean: Double, p95: Double) {
        var rng = SplitMix64(seed: seed)
        let gridPlane: [Vec2] = (0..<9).map { Vec2(Double($0 % 3) * width / 2, Double($0 / 3) * depth / 2) }
        let cornerPlane = [Vec2(0, 0), Vec2(width, 0), Vec2(width, depth), Vec2(0, depth)]
        // キーが並ぶ範囲(登録範囲の内側 80%)
        var targets: [Vec2] = []
        for i in 0..<10 { for j in 0..<4 {
            targets.append(Vec2(width * (0.1 + 0.8 * Double(i) / 9), depth * (0.1 + 0.8 * Double(j) / 3)))
        } }
        var errors: [Double] = []
        for _ in 0..<trials {
            let planePoints = method == .finger9 ? gridPlane : cornerPlane
            let observed: [Vec2] = planePoints.map { p in
                switch method {
                case .tap4:
                    return camera.project(p, width: width, depth: depth)
                        + Vec2(rng.nextGaussian(), rng.nextGaussian()) * noise.tapNoisePx
                case .finger4, .finger9:
                    let touched = p + Vec2(rng.nextGaussian(), rng.nextGaussian()) * noise.fingertipBiasCm
                    let averagedNoise = noise.keypointNoisePx / noise.holdFrames.squareRoot()
                    return camera.project(touched, width: width, depth: depth)
                        + Vec2(rng.nextGaussian(), rng.nextGaussian()) * averagedNoise
                }
            }
            let plane = method == .finger9
                ? DeskPlane(gridPoints: observed, widthCm: width, depthCm: depth)
                : DeskPlane(imageCorners: observed, widthCm: width, depthCm: depth)
            guard let h = plane.imageToPlane else { continue }
            for target in targets {
                guard let estimated = h.apply(camera.project(target, width: width, depth: depth)) else { continue }
                errors.append(estimated.distance(to: target) * 10)  // cm → mm
            }
        }
        errors.sort()
        let mean = errors.reduce(0, +) / Double(max(errors.count, 1))
        let p95 = errors.isEmpty ? 0 : errors[min(errors.count - 1, Int(Double(errors.count) * 0.95))]
        return (mean, p95)
    }
}
