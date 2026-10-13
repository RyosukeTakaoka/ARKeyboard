import Foundation

/// 1フレーム処理した結果(ViewModel が画面に反映する)
struct EngineOutput {
    /// 左右を割り当てた手
    var hands: [Chirality: HandObservation] = [:]
    /// キー配置の基準にしている手の座標系(画面にキーを描くのに使う)
    var layoutFrames: [Chirality: HandFrame] = [:]
    /// このフレームでキャリブレーションが完了したら、その結果
    var calibrationFinished: CalibrationResult?
}

/// キーボードの「頭脳」。カメラにも画面にも依存しない純粋なロジックだけを持ちます。
///
/// VisionFrame(手の認識結果)を1つ受け取るたびに、
///   左右の割り当て → 手の座標系 → キャリブレーション
/// の順に処理して、EngineOutput を返します。
/// UI に依存しないので、単体テストで動作を確かめられます。
final class KeyboardEngine {
    var settings: KeyboardSettings

    /// キャリブレーション
    let calibrator = Calibrator()
    /// 現在のキャリブレーション結果(未実施なら nil)
    private(set) var calibration: CalibrationResult?

    /// 手ごとの「平滑化した」手の座標系(手ぶれでキー配置が震えないようにするため)
    private var smoothedFrames: [Chirality: HandFrame] = [:]

    init(settings: KeyboardSettings = KeyboardSettings()) {
        self.settings = settings
    }

    func startCalibration() {
        calibrator.start()
    }

    func setCalibration(_ result: CalibrationResult?) {
        calibration = result
    }

    /// 1フレーム分の処理
    func process(_ frame: VisionFrame) -> EngineOutput {
        var output = EngineOutput()
        let hands = assignHands(frame.hands)
        output.hands = hands

        // 手の座標系を作り、前のフレームの値となめらかにつなぐ
        for chirality in Chirality.allCases {
            if let hand = hands[chirality],
               let live = HandFrame(hand: hand, minConfidence: settings.minConfidence) {
                if let previous = smoothedFrames[chirality] {
                    smoothedFrames[chirality] = previous.smoothed(toward: live, alpha: 1 - settings.layoutSmoothing)
                } else {
                    smoothedFrames[chirality] = live
                }
            } else {
                // 手が見えなくなったら、古い座標系は捨てる(再び見えたときに古い位置から動き出さないように)
                smoothedFrames[chirality] = nil
            }
        }

        // キャリブレーション中は、それだけを行う
        if calibrator.isActive {
            if let result = calibrator.process(hands: hands, timestamp: frame.timestamp) {
                calibration = result
                output.calibrationFinished = result
            }
        }

        if calibration != nil {
            output.layoutFrames = smoothedFrames
        }
        return output
    }

    /// Vision の検出結果(最大2つ)を「左手」「右手」に割り当てます。
    ///
    /// 基本は Vision の chirality(左右判定)を使います。ただし、
    /// - 判定できなかった(unknown)とき
    /// - 2つとも同じ手だと判定されたとき
    /// は、手の形(人差し指が forward のどちら側にあるか)から推定した左右で補います。
    func assignHands(_ observations: [HandObservation]) -> [Chirality: HandObservation] {
        var result: [Chirality: HandObservation] = [:]
        var unresolved: [HandObservation] = []

        for observation in observations {
            if var chirality = observation.chirality {
                if settings.swapHands { chirality = chirality.opposite }
                if result[chirality] == nil {
                    result[chirality] = observation
                    continue
                }
            }
            unresolved.append(observation)
        }

        for observation in unresolved {
            // 形からの推定(手のひらを下にして上から撮っている前提)
            var guess: Chirality? = HandFrame(hand: observation, minConfidence: settings.minConfidence)?.handedness
            if settings.swapHands { guess = guess?.opposite }
            if let guess, result[guess] == nil {
                result[guess] = observation
            } else if let free = Chirality.allCases.first(where: { result[$0] == nil }) {
                result[free] = observation
            }
        }
        return result
    }
}
