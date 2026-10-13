import CoreML
import Foundation

/// タップ推定レベルB の学習モデルを Core ML で動かす。
///
/// tools/eval/train_levelb.py が作った LevelBTapModel.mlmodel を ARKeyboard/Resources/Model/ に置くと、
/// Xcode がビルド時に .mlmodelc(端末で動かせる形)に変換してアプリに入れます。
/// 入力: "features"(22 個の数), 出力: "output"(3 個: タップらしさのロジット, dx, dy)
final class CoreMLTapClassifier: TapClassifier {
    private let model: MLModel

    init?(bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: "LevelBTapModel", withExtension: "mlmodelc"),
              let model = try? MLModel(contentsOf: url) else { return nil }
        self.model = model
    }

    func evaluate(_ features: [Double]) -> (tapProbability: Double, offset: Vec2) {
        guard let array = try? MLMultiArray(shape: [NSNumber(value: features.count)], dataType: .double) else {
            return (1, .zero)
        }
        for (i, v) in features.enumerated() { array[i] = NSNumber(value: v) }
        guard let input = try? MLDictionaryFeatureProvider(dictionary: ["features": MLFeatureValue(multiArray: array)]),
              let result = try? model.prediction(from: input),
              let output = result.featureValue(for: "output")?.multiArrayValue,
              output.count >= 3 else {
            return (1, .zero)
        }
        let logit = output[0].doubleValue
        return (1 / (1 + exp(-logit)), Vec2(output[1].doubleValue, output[2].doubleValue))
    }
}

/// レベルB のモデルを探して読み込む(Core ML を優先し、無ければ JSON の重み)
enum LevelBModelLoader {
    static func load(bundle: Bundle = .main) -> (classifier: TapClassifier, description: String)? {
        if let coreML = CoreMLTapClassifier(bundle: bundle) {
            return (coreML, "Core ML(LevelBTapModel.mlmodel)")
        }
        if let url = bundle.url(forResource: "LevelBTapModel", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let network = try? JSONDecoder().decode(DenseNetwork.self, from: data) {
            return (network, "JSON(LevelBTapModel.json)")
        }
        return nil
    }
}
