import CoreVideo
import ImageIO

/// 手の追跡器の共通ルール(プロトコル)。
///
/// ## なぜプロトコルにするのか
/// 「Vision で追跡する」「MediaPipe で追跡する」など、実装を差し替えて比べられるようにするためです。
/// カメラ側(CameraManager)は「HandTracker に従っている何か」に画像を渡すだけなので、
/// どの実装が入っていても同じように動きます。
///
/// 実装:
/// - VisionHandTracker … Apple の Vision(2D)
/// - MediaPipeHandTracker … Google の MediaPipe(3D。CocoaPods で導入したときだけ使える)
protocol HandTracker: AnyObject {
    var kind: HandTrackerKind { get }

    /// 1コマから手を検出する。重い処理なので、必ずバックグラウンドのキューから呼ぶこと。
    /// - Parameters:
    ///   - pixelBuffer: カメラから届いた画像(センサーの向きのまま=横長)
    ///   - orientation: 画像の向き(縦向きの背面カメラなら `.right`)
    ///   - timestamp: 撮影時刻(秒、端末起動からの時間)
    func detect(in pixelBuffer: CVPixelBuffer,
                orientation: CGImagePropertyOrientation,
                timestamp: Double) -> VisionFrame
}
