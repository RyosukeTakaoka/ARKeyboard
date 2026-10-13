import Foundation
import CoreVideo
import ImageIO

// MediaPipe(Google)の Hand Landmarker で手を追跡する(HandTracker の実装の1つ)。
//
// ## 導入方法(任意。入れなくてもアプリは Vision で動きます)
// 1. CocoaPods を入れる(ターミナルで `sudo gem install cocoapods`)
// 2. リポジトリのルートの Podfile.example を Podfile という名前でコピーし、`pod install`
// 3. 以後は ARKeyboard.xcworkspace を開く(.xcodeproj ではなく)
// 4. 学習済みモデル hand_landmarker.task を Google の公式ページからダウンロードし、
//    ARKeyboard/Resources/Model/ に置く
//    (公式ガイド: https://ai.google.dev/edge/mediapipe/solutions/vision/hand_landmarker/ios)
// 5. 設定 → 手の追跡 → MediaPipe を選ぶ
//
// ## Vision との違い
// - 21 点それぞれに奥行き z(手首を基準にした相対的な値)がある(JointPoint.z に入れる)
// - 左右の判定(handedness)は「自撮り(鏡像)の画像」を前提にしている。
//   背面カメラの画像は鏡像ではないので、左右を入れ替えて使う。
// - 関節ごとの信頼度は無いので、手全体の確からしさ(handedness の score)を全関節に使う。
//
// ⚠️ この環境(Linux)ではMediaPipe を入れたビルドを確かめられていません。実機での確認が必要です。

#if canImport(MediaPipeTasksVision)
import MediaPipeTasksVision
import UIKit

final class MediaPipeHandTracker: HandTracker {
    let kind: HandTrackerKind = .mediaPipe
    private let landmarker: HandLandmarker
    /// MediaPipe の video モードは、時刻(ミリ秒)が必ず増えていく必要がある
    private var lastTimestampMs = -1

    /// モデルファイルがアプリに入っているか
    static var isAvailable: Bool {
        Bundle.main.path(forResource: "hand_landmarker", ofType: "task") != nil
    }

    /// MediaPipe の 21 点の番号 → アプリの関節(MediaPipe の thumb_mcp は、アプリの thumbMP に当たる)
    private static let jointOrder: [Joint] = [
        .wrist,
        .thumbCMC, .thumbMP, .thumbIP, .thumbTip,
        .indexMCP, .indexPIP, .indexDIP, .indexTip,
        .middleMCP, .middlePIP, .middleDIP, .middleTip,
        .ringMCP, .ringPIP, .ringDIP, .ringTip,
        .littleMCP, .littlePIP, .littleDIP, .littleTip,
    ]

    init?() {
        guard let path = Bundle.main.path(forResource: "hand_landmarker", ofType: "task") else { return nil }
        let options = HandLandmarkerOptions()
        options.baseOptions.modelAssetPath = path
        options.runningMode = .video
        options.numHands = 2
        options.minHandDetectionConfidence = 0.5
        options.minHandPresenceConfidence = 0.5
        options.minTrackingConfidence = 0.5
        guard let landmarker = try? HandLandmarker(options: options) else { return nil }
        self.landmarker = landmarker
    }

    func detect(in pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation, timestamp: Double) -> VisionFrame {
        let started = ProcessInfo.processInfo.systemUptime
        let bufferWidth = Double(CVPixelBufferGetWidth(pixelBuffer))
        let bufferHeight = Double(CVPixelBufferGetHeight(pixelBuffer))
        let imageSize = orientation.swapsWidthAndHeight ? Vec2(bufferHeight, bufferWidth) : Vec2(bufferWidth, bufferHeight)

        var hands: [HandObservation] = []
        // 時刻が戻ったり同じだったりすると MediaPipe がエラーになるので、必ず増やす
        let ms = max(Int(timestamp * 1000), lastTimestampMs + 1)
        lastTimestampMs = ms
        if let image = try? MPImage(pixelBuffer: pixelBuffer, orientation: Self.uiOrientation(orientation)),
           let result = try? landmarker.detect(videoFrame: image, timestampInMilliseconds: ms) {
            for (i, landmarks) in result.landmarks.enumerated() {
                let category = i < result.handedness.count ? result.handedness[i].first : nil
                let score = Double(category?.score ?? 0.5)
                var joints: [Joint: JointPoint] = [:]
                for (j, landmark) in landmarks.enumerated() where j < Self.jointOrder.count {
                    // MediaPipe の座標は 0〜1、原点は左上(Vision と違って上下の反転は不要)
                    joints[Self.jointOrder[j]] = JointPoint(position: Vec2(Double(landmark.x) * imageSize.x,
                                                                          Double(landmark.y) * imageSize.y),
                                                            confidence: score,
                                                            z: Double(landmark.z))
                }
                // 鏡像前提の判定なので、背面カメラでは入れ替える
                let chirality: Chirality?
                switch category?.categoryName {
                case "Left": chirality = .right
                case "Right": chirality = .left
                default: chirality = nil
                }
                hands.append(HandObservation(chirality: chirality, joints: joints))
            }
        }
        var frame = VisionFrame(timestamp: timestamp, imageSize: imageSize, hands: hands)
        frame.trackerKind = kind
        frame.processingTime = ProcessInfo.processInfo.systemUptime - started
        return frame
    }

    private static func uiOrientation(_ o: CGImagePropertyOrientation) -> UIImage.Orientation {
        switch o {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        }
    }
}

#else

/// MediaPipe を導入していないときの代わり(使えないことを伝えるだけ)
final class MediaPipeHandTracker: HandTracker {
    let kind: HandTrackerKind = .mediaPipe
    static var isAvailable: Bool { false }
    init?() { return nil }
    func detect(in pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation, timestamp: Double) -> VisionFrame {
        VisionFrame(timestamp: timestamp, imageSize: .zero, hands: [])
    }
}

#endif

/// 手の追跡器を作る
enum HandTrackerFactory {
    static func isAvailable(_ kind: HandTrackerKind) -> Bool {
        switch kind {
        case .vision: return true
        case .mediaPipe: return MediaPipeHandTracker.isAvailable
        }
    }

    /// 指定の追跡器を作る(使えなければ Vision)
    static func make(_ kind: HandTrackerKind) -> HandTracker {
        switch kind {
        case .vision: return VisionHandTracker()
        case .mediaPipe: return MediaPipeHandTracker() ?? VisionHandTracker()
        }
    }
}
