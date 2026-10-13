import AVFoundation

/// カメラの状態。画面の出し分け(「許可してください」「実機で実行してください」など)に使います。
enum CameraStatus: Equatable {
    /// まだ開始していない
    case idle
    /// 映像が流れている
    case running
    /// ユーザーがカメラの使用を許可していない
    case denied
    /// カメラが存在しない(シミュレーターなど)
    case unavailable
    /// 設定中にエラーが起きた
    case failed(String)
}

/// 「1コマ分の手の認識結果」を届けてくれるもの(カメラ)の共通ルール。
/// 通常のカメラ(CameraManager)と、LiDAR 対応機で使う ARKit 版の両方がこれに従います。
protocol FrameSource: AnyObject {
    /// 1コマ処理するたびに **メインスレッドで** 呼ばれるクロージャ
    var onFrame: ((VisionFrame) -> Void)? { get set }
    /// 開始(結果はメインスレッドで completion に届く)
    func start(completion: @escaping (CameraStatus) -> Void)
    /// 停止
    func stop()
}

/// 背面カメラの映像を取り出すクラス(AVFoundation を担当)。
///
/// ## AVFoundation の基本の形
/// AVFoundation では、次の3つを「つなぐ」ことでカメラを使います。
/// 1. 入力 (AVCaptureDeviceInput) … どのカメラを使うか
/// 2. セッション (AVCaptureSession) … 入力と出力をつなぐ「配線盤」
/// 3. 出力 … 画面に映す (AVCaptureVideoPreviewLayer) や、1コマずつ受け取る (AVCaptureVideoDataOutput)
///
/// ## スレッド(キュー)の使い分け
/// - メインスレッド: 画面の描画とユーザー操作だけ。重い処理をすると画面がカクつく。
/// - sessionQueue: セッションの設定・開始・停止(数百ミリ秒かかることがある)
/// - videoQueue: 1コマごとの処理(Vision の手の検出)。1コマ数十ミリ秒かかる。
/// 結果(VisionFrame)だけをメインスレッドに渡して、画面を更新します。
final class CameraManager: NSObject, FrameSource {
    /// 入力と出力をつなぐセッション。プレビュー表示(CameraPreviewView)からも参照します。
    let session = AVCaptureSession()

    /// 1コマ処理するたびに(メインスレッドで)呼ばれる
    var onFrame: ((VisionFrame) -> Void)?

    /// 1コマずつ画像を受け取るための出力
    private let videoOutput = AVCaptureVideoDataOutput()

    /// 1コマごとの処理を行うキュー。qos(優先度)を高めにして、遅れにくくします。
    private let videoQueue = DispatchQueue(label: "ARKeyboard.camera.video", qos: .userInitiated)

    /// 手の検出(videoQueue からだけ使う)
    private let detector = HandPoseDetector()

    /// セッションの開始・停止は時間がかかる(数百ミリ秒ブロックする)ので、
    /// メインスレッド(画面を描くスレッド)ではなく専用のキューで行います。
    /// メインスレッドで行うと、その間アプリの画面が固まってしまいます。
    private let sessionQueue = DispatchQueue(label: "ARKeyboard.camera.session")

    /// 一度だけ設定するためのフラグ(sessionQueue の中でだけ読み書きします)
    private var isConfigured = false

    /// この端末でカメラが使えるかどうか。
    /// シミュレーターにはカメラがないので、必ず false を返します。
    static var isCameraAvailable: Bool {
        #if targetEnvironment(simulator)
        // `#if targetEnvironment(simulator)` はコンパイル時の分岐です。
        // シミュレーター向けにビルドしたときだけ、この行が使われます。
        return false
        #else
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
        #endif
    }

    /// カメラの使用許可を確認し、許可されていればセッションを開始します。
    /// - Parameter completion: 結果をメインスレッドで受け取るクロージャ
    func start(completion: @escaping (CameraStatus) -> Void) {
        // カメラがない環境(シミュレーター)では、ここで止めます。
        // AVFoundation の API をそのまま呼んでもクラッシュはしませんが、
        // 「何も映らない理由」をユーザーに伝えるために明示的に判定しています。
        guard Self.isCameraAvailable else {
            completion(.unavailable)
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            // すでに許可されている
            startSession(completion: completion)
        case .notDetermined:
            // まだ聞いていない → 許可ダイアログを出す(文言は Info.plist の NSCameraUsageDescription)
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    self?.startSession(completion: completion)
                } else {
                    // requestAccess のコールバックはメインスレッドとは限らないので、明示的に戻す
                    DispatchQueue.main.async { completion(.denied) }
                }
            }
        case .denied, .restricted:
            completion(.denied)
        @unknown default:
            completion(.denied)
        }
    }

    /// セッションを止めます(画面が閉じたときやバックグラウンドに入ったとき)。
    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    private func startSession(completion: @escaping (CameraStatus) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            do {
                if !self.isConfigured {
                    try self.configureSession()
                    self.isConfigured = true
                }
                if !self.session.isRunning {
                    self.session.startRunning()
                }
                DispatchQueue.main.async { completion(.running) }
            } catch {
                DispatchQueue.main.async { completion(.failed(error.localizedDescription)) }
            }
        }
    }

    /// 入力(背面カメラ)と出力をセッションにつなぎます。
    private func configureSession() throws {
        // beginConfiguration 〜 commitConfiguration の間の変更は、最後にまとめて反映されます。
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        // 1280x720 は、手の認識には十分な解像度で、処理も軽いのでこれを選びます。
        if session.canSetSessionPreset(.hd1280x720) {
            session.sessionPreset = .hd1280x720
        }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw CameraError.noCamera
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw CameraError.cannotAddInput }
        session.addInput(input)

        // 1コマずつ受け取る出力の設定
        // ・ピクセル形式は、カメラの標準(YUV 4:2:0)にしておくと変換が不要で速い。Vision もこの形式を直接読めます。
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        // ・処理が間に合わないコマは捨てる。古いコマを溜めて処理すると「遅れて反応する」キーボードになるため、
        //   常に最新のコマだけを処理する方が良い。
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        guard session.canAddOutput(videoOutput) else { throw CameraError.cannotAddOutput }
        session.addOutput(videoOutput)

        // タップは一瞬(50〜100ミリ秒)の動きなので、コマ数が多いほど検出しやすい。
        // 対応していれば 60fps にします(対応していなければ標準の 30fps のまま)。
        configureFrameRate(device: device, preferredFPS: 60)
    }

    /// 1280x720 で指定の fps に対応したフォーマットを探して設定します。
    private func configureFrameRate(device: AVCaptureDevice, preferredFPS: Double) {
        let candidates = device.formats.filter { format in
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let supportsFPS = format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= preferredFPS }
            return dimensions.width == 1280 && dimensions.height == 720 && supportsFPS
        }
        // ピクセル形式が出力と同じ(フルレンジ YUV)ものを優先(変換の手間が減る)
        let preferred = candidates.first {
            CMFormatDescriptionGetMediaSubType($0.formatDescription) == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        } ?? candidates.first
        guard let format = preferred else {
            print("[CameraManager] \(Int(preferredFPS))fps 対応フォーマットが無いため、標準設定のまま使います")
            return
        }
        do {
            try device.lockForConfiguration()
            device.activeFormat = format
            // 最短フレーム間隔 = 1/60秒(最大 60fps)
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(preferredFPS))
            // 最長フレーム間隔 = 1/30秒(暗い場所では露光時間を延ばすため 30fps まで下がってよい)
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
            device.unlockForConfiguration()
        } catch {
            print("[CameraManager] フレームレートを設定できませんでした: \(error.localizedDescription)")
        }
    }
}

/// カメラ設定で起きうるエラー。`LocalizedError` にすると、localizedDescription に日本語を出せます。
enum CameraError: LocalizedError {
    case noCamera
    case cannotAddInput
    case cannotAddOutput

    var errorDescription: String? {
        switch self {
        case .noCamera: return "背面カメラが見つかりません。"
        case .cannotAddInput: return "カメラ入力をセッションに追加できませんでした。"
        case .cannotAddOutput: return "映像出力をセッションに追加できませんでした。"
        }
    }
}

// MARK: - 1コマごとの処理

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    /// カメラから1コマ届くたびに、videoQueue(バックグラウンド)で呼ばれます。
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        // 撮影時刻(秒)。処理の遅れに影響されない正確な時刻なので、速度の計算に使います。
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds

        // 背面カメラ + 縦向き画面なので、向きは .right(詳しくは HandPoseDetector のコメント)
        let frame = detector.detect(in: pixelBuffer, orientation: .right, timestamp: timestamp)

        // 画面の更新はメインスレッドで行う決まりなので、結果だけをメインスレッドに渡します。
        DispatchQueue.main.async { [weak self] in
            self?.onFrame?(frame)
        }
    }
}
