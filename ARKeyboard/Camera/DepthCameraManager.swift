import ARKit
import AVFoundation
import CoreVideo

/// LiDAR 搭載機で使うカメラ(ARKit 版)。
///
/// ## なぜ AVCaptureSession ではなく ARKit を使うのか
/// LiDAR の深度(scene depth)は ARKit からしか取得できません。
/// また、ARKit の ARSession と AVCaptureSession は同時に同じカメラを使えないので、
/// LiDAR モードのときはカメラ自体を ARKit に切り替えます。
/// 手の検出は通常モードと同じく Vision(HandPoseDetector)で行います。
final class DepthCameraManager: NSObject, FrameSource {
    let session = ARSession()
    var onFrame: ((VisionFrame) -> Void)?

    /// ARKit からフレームを受け取るキュー
    private let delegateQueue = DispatchQueue(label: "ARKeyboard.ar.delegate")
    /// Vision の処理をするキュー
    private let processingQueue = DispatchQueue(label: "ARKeyboard.ar.vision", qos: .userInitiated)
    private let detector = HandPoseDetector()
    /// 処理中なら次のフレームは捨てる(delegateQueue の中でだけ読み書きする)。
    /// ARKit は 60fps でフレームを送ってくるので、全部処理しようとすると遅れが溜まるため。
    private var isProcessing = false

    /// この端末で LiDAR の深度が使えるか
    static var isSupported: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
        #endif
    }

    func start(completion: @escaping (CameraStatus) -> Void) {
        guard Self.isSupported else {
            completion(.unavailable)
            return
        }
        // カメラの使用許可は通常モードと共通(同じ NSCameraUsageDescription が使われる)
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            run(completion: completion)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted { self?.run(completion: completion) } else { completion(.denied) }
                }
            }
        default:
            completion(.denied)
        }
    }

    private func run(completion: @escaping (CameraStatus) -> Void) {
        let configuration = ARWorldTrackingConfiguration()
        // smoothedSceneDepth は、数フレーム分をならしてノイズを減らした深度。使えればこちらを使う
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            configuration.frameSemantics = [.smoothedSceneDepth]
        } else {
            configuration.frameSemantics = [.sceneDepth]
        }
        session.delegate = self
        session.delegateQueue = delegateQueue
        session.run(configuration, options: [.resetTracking])
        DispatchQueue.main.async { completion(.running) }
    }

    func stop() {
        session.pause()
    }
}

extension DepthCameraManager: ARSessionDelegate {
    /// ARKit から新しいフレームが届くたびに(delegateQueue で)呼ばれる
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard !isProcessing else { return }
        isProcessing = true

        // ⚠️ ARFrame 自体を長く持ち続けると、ARKit がフレームを再利用できなくなり警告が出るので、
        //    必要なもの(画像・時刻・深度のコピー)だけを取り出してから別キューに渡す。
        let pixelBuffer = frame.capturedImage
        let timestamp = frame.timestamp
        let depthData = frame.smoothedSceneDepth ?? frame.sceneDepth
        let depthMap = depthData.flatMap { DepthMap(copying: $0.depthMap) }

        processingQueue.async { [weak self] in
            guard let self else { return }
            // ARKit の画像もセンサーの向き(横長)なので、縦向き表示では .right(HandPoseDetector 参照)
            var visionFrame = self.detector.detect(in: pixelBuffer, orientation: .right, timestamp: timestamp)
            visionFrame.depthMap = depthMap
            let result = visionFrame
            DispatchQueue.main.async { self.onFrame?(result) }
            self.delegateQueue.async { self.isProcessing = false }
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        print("[DepthCameraManager] ARSession エラー: \(error.localizedDescription)")
    }
}
