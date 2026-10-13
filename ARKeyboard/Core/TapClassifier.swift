import Foundation

/// タップ推定レベルB(学習モデル)の共通ルール。
/// 特徴量(TapFeatures)を受け取り、「タップである確率」と「位置の補正」を返す。
protocol TapClassifier {
    func evaluate(_ features: [Double]) -> (tapProbability: Double, offset: Vec2)
}

/// レベルB の特徴量の作り方(アプリと評価ツールで同じものを使う)。
///
/// 特徴量(合計 22 個):
/// - [0..<12] 直近 6 フレームの「手のひらに対する指先の位置」(手の座標、x と y)を、最新のフレームの値を引いて並べたもの
///   (=止まった位置から見て、どう動いてきたか)
/// - [12] 下ろした速さ ÷ しきい値、[13] 下ろした距離
/// - [14..<19] 指の種類(親指・人差し指・中指・薬指・小指のどれかが 1)
/// - [19] 音のオンセットがあったか(0/1)、[20] その強さ、[21] カメラとのずれ(秒)
enum TapFeatures {
    static let historyLength = 6
    static let count = historyLength * 2 + 2 + 5 + 3

    /// カメラの情報だけの部分(音の部分は 0 で埋めておき、融合の後で埋める)
    static func base(history: [Vec2], peakRatio: Double, travel: Double, finger: Finger) -> [Double] {
        var values: [Double] = []
        let recent = Array(history.suffix(historyLength))
        let latest = recent.last ?? .zero
        // 足りない分は、いちばん古い値で埋める
        let padded = Array(repeating: recent.first ?? .zero, count: historyLength - recent.count) + recent
        for p in padded {
            values += [p.x - latest.x, p.y - latest.y]
        }
        values += [peakRatio, travel]
        values += Finger.allCases.map { $0 == finger ? 1 : 0 }
        values += [0, 0, 0]
        return values
    }

    /// 音の部分を埋める
    static func withAudio(_ base: [Double], onset: OnsetEvent?, tapTime: Double) -> [Double] {
        var values = base
        guard values.count == count else { return values }
        if let onset {
            values[19] = 1
            values[20] = onset.strength
            values[21] = onset.time - tapTime
        }
        return values
    }
}

/// 小さなニューラルネットワーク(全結合層を重ねたもの)を、Swift だけで計算する。
///
/// Python(tools/eval/train_levelb.py)で学習した重みを JSON で読み込みます。
/// Core ML の版(CoreMLTapClassifier)と同じ結果になります。Linux でもテストできるよう、こちらも用意しています。
struct DenseNetwork: TapClassifier, Codable {
    struct Layer: Codable {
        /// 重み W[出力][入力]
        var weights: [[Double]]
        var bias: [Double]
        /// "relu" または "linear"
        var activation: String
    }

    /// 入力の標準化(学習データの平均と標準偏差)
    var inputMean: [Double]
    var inputStd: [Double]
    var layers: [Layer]

    /// 出力: [タップらしさ(ロジット), dx, dy]
    func forward(_ input: [Double]) -> [Double] {
        var x = zip(zip(input, inputMean), inputStd).map { ($0.0 - $0.1) / max($1, 1e-9) }
        for layer in layers {
            var y = [Double](repeating: 0, count: layer.bias.count)
            for o in 0..<layer.bias.count {
                var sum = layer.bias[o]
                let w = layer.weights[o]
                for i in 0..<min(w.count, x.count) { sum += w[i] * x[i] }
                y[o] = layer.activation == "relu" ? max(0, sum) : sum
            }
            x = y
        }
        return x
    }

    func evaluate(_ features: [Double]) -> (tapProbability: Double, offset: Vec2) {
        let out = forward(features)
        guard out.count >= 3 else { return (1, .zero) }
        return (1 / (1 + exp(-out[0])), Vec2(out[1], out[2]))
    }
}
