import Foundation
import Vision
import ImageIO
import CoreVideo

/// Vision フレームワークで「手の関節点」を検出するクラス。
///
/// ## カメラの向きの扱い(とても大事)
/// iPhone のカメラセンサーは、端末を**横向き**(ホームボタン/画面下部が右側)にしたときに
/// 正しい向きになるよう取り付けられています。そのため、端末を縦向きで持っていても、
/// カメラから届く画像(ピクセルバッファ)は **横長(例: 1280x720)で、90度寝た状態** です。
///
/// そこで Vision に「この画像は `.right` の向きで記録されている」と教えます。
/// `.right` = 「表示するには時計回りに90度回す必要がある画像」という意味です。
/// すると Vision は画像を内部で正しい向き(縦長 720x1280)に起こしてから手を探し、
/// 結果の座標も **起こした後の縦長画像** を基準に返してくれます。
///
/// - 背面カメラ + 縦向き → `.right`(このアプリはこれだけを使う)
/// - 参考: 前面カメラ + 縦向き → `.leftMirrored`(鏡像になるため)
///
/// このアプリは画面を縦向きに固定しているので、向きは常に `.right` で済みます。
/// (手の座標系 HandFrame は画像の上下左右を仮定しないので、仮に向きがずれても
///  キー配置そのものは手の向きに合わせて作られます。)
final class HandPoseDetector {
    /// Vision へのリクエスト。毎フレーム作り直すと無駄なので、1つを使い回します。
    /// (使い回すので、このクラスは1つのスレッド(キュー)からだけ呼ぶ前提です)
    private let request: VNDetectHumanHandPoseRequest = {
        let request = VNDetectHumanHandPoseRequest()
        // 両手を検出したいので最大2つ(初期値も2ですが、意図を明示するために書いています)
        request.maximumHandCount = 2
        return request
    }()

    /// アプリの Joint と Vision の JointName の対応表
    private static let jointNames: [(Joint, VNHumanHandPoseObservation.JointName)] = [
        (.wrist, .wrist),
        (.thumbCMC, .thumbCMC), (.thumbMP, .thumbMP), (.thumbIP, .thumbIP), (.thumbTip, .thumbTip),
        (.indexMCP, .indexMCP), (.indexPIP, .indexPIP), (.indexDIP, .indexDIP), (.indexTip, .indexTip),
        (.middleMCP, .middleMCP), (.middlePIP, .middlePIP), (.middleDIP, .middleDIP), (.middleTip, .middleTip),
        (.ringMCP, .ringMCP), (.ringPIP, .ringPIP), (.ringDIP, .ringDIP), (.ringTip, .ringTip),
        (.littleMCP, .littleMCP), (.littlePIP, .littlePIP), (.littleDIP, .littleDIP), (.littleTip, .littleTip),
    ]

    /// 1コマ分の画像から手を検出します。
    ///
    /// ⚠️ Vision の処理は重い(1コマ数十ミリ秒)ので、**メインスレッドでは呼ばないでください**。
    /// CameraManager がカメラ専用のバックグラウンドキューから呼び出しています。
    ///
    /// - Parameters:
    ///   - pixelBuffer: カメラから届いた画像(センサーの向きのまま=横長)
    ///   - orientation: 画像の向き(縦向きの背面カメラなら `.right`)
    ///   - timestamp: 撮影時刻(秒)
    func detect(in pixelBuffer: CVPixelBuffer,
                orientation: CGImagePropertyOrientation,
                timestamp: Double) -> VisionFrame {
        // 向きを補正した後の画像サイズ。90度回転する向きなら幅と高さが入れ替わります。
        let bufferWidth = Double(CVPixelBufferGetWidth(pixelBuffer))
        let bufferHeight = Double(CVPixelBufferGetHeight(pixelBuffer))
        let imageSize = orientation.swapsWidthAndHeight
            ? Vec2(bufferHeight, bufferWidth)
            : Vec2(bufferWidth, bufferHeight)

        var hands: [HandObservation] = []
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
        do {
            try handler.perform([request])
            for observation in request.results ?? [] {
                hands.append(convert(observation, imageSize: imageSize))
            }
        } catch {
            // 1コマ失敗しても次のコマで回復するので、ログだけ出して続けます。
            print("[HandPoseDetector] Vision エラー: \(error.localizedDescription)")
        }
        return VisionFrame(timestamp: timestamp, imageSize: imageSize, hands: hands)
    }

    /// Vision の結果を、アプリ内の HandObservation(ピクセル座標・原点左上)に変換します。
    private func convert(_ observation: VNHumanHandPoseObservation, imageSize: Vec2) -> HandObservation {
        var joints: [Joint: JointPoint] = [:]
        if let points = try? observation.recognizedPoints(.all) {
            for (joint, name) in Self.jointNames {
                guard let point = points[name] else { continue }
                // ★ 座標変換の要(かなめ)
                // Vision: 0〜1 に正規化 & 原点は「左下」(y は上向き)
                // アプリ: ピクセル単位 & 原点は「左上」(y は下向き)
                //   → x はそのまま幅を掛ける、y は (1 − y) にして上下を反転してから高さを掛ける
                let position = Vec2(Double(point.location.x) * imageSize.x,
                                    (1 - Double(point.location.y)) * imageSize.y)
                joints[joint] = JointPoint(position: position, confidence: Double(point.confidence))
            }
        }

        // 左右の判定(chirality)。iOS 15 以降で使えます。
        // 判定できないとき(.unknown)は nil にしておき、後で位置関係から推定します。
        let chirality: Chirality?
        switch observation.chirality {
        case .left: chirality = .left
        case .right: chirality = .right
        default: chirality = nil
        }
        return HandObservation(chirality: chirality, joints: joints)
    }
}

extension CGImagePropertyOrientation {
    /// 90度(または270度)回転する向きかどうか。そうなら、表示上の幅と高さが入れ替わります。
    var swapsWidthAndHeight: Bool {
        switch self {
        case .left, .right, .leftMirrored, .rightMirrored:
            return true
        default:
            return false
        }
    }
}
