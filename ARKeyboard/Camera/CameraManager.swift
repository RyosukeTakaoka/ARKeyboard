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

/// 背面カメラの映像を取り出すクラス(AVFoundation を担当)。
///
/// ## AVFoundation の基本の形
/// AVFoundation では、次の3つを「つなぐ」ことでカメラを使います。
/// 1. 入力 (AVCaptureDeviceInput) … どのカメラを使うか
/// 2. セッション (AVCaptureSession) … 入力と出力をつなぐ「配線盤」
/// 3. 出力 … 画面に映す (AVCaptureVideoPreviewLayer) や、1コマずつ受け取る (AVCaptureVideoDataOutput)
final class CameraManager: NSObject {
    /// 入力と出力をつなぐセッション。プレビュー表示(CameraPreviewView)からも参照します。
    let session = AVCaptureSession()

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
