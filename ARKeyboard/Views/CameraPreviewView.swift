import SwiftUI
import AVFoundation

/// カメラ映像を画面に表示する View。
///
/// SwiftUI にはカメラ映像を直接表示する部品がないため、UIKit の UIView を
/// `UIViewRepresentable` で包んで SwiftUI から使えるようにしています。
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        // resizeAspectFill: 縦横比を保ったまま画面いっぱいに拡大し、はみ出た部分は切り取る。
        // ★ 重要: 指先の座標を画面座標に変換するとき(CoordinateConverter)も、
        //   これと「同じ拡大・切り取り方」で計算しています。ここを変えたら変換側も変える必要があります。
        view.previewLayer.videoGravity = .resizeAspectFill
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {}

    /// レイヤーの種類そのものを AVCaptureVideoPreviewLayer にした UIView。
    /// こうすると、View のサイズが変わったときにレイヤーも自動で同じサイズになります。
    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var previewLayer: AVCaptureVideoPreviewLayer {
            // layerClass を上で指定しているので、この強制キャストは必ず成功します。
            layer as! AVCaptureVideoPreviewLayer
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            // カメラのセンサーは「横長」に取り付けられています。
            // このアプリは縦向き(ポートレート)固定なので、プレビューを 90 度回して縦向きに表示します。
            // (iOS 17 からは videoOrientation ではなく videoRotationAngle を使います)
            if let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        }
    }
}
