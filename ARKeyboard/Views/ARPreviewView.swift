import SwiftUI
import ARKit
import SceneKit

/// LiDAR モードのときのカメラ映像の表示(ARKit のセッションの映像を映す)。
/// ARSCNView も、通常のプレビューと同じく「縦横比を保って画面いっぱい(aspectFill)」で映すので、
/// CoordinateConverter の変換はそのまま使えます。
struct ARPreviewView: UIViewRepresentable {
    let session: ARSession

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        // 自分で作った ARSession の映像を表示する
        view.session = session
        // 3D の物は置かないので、ライトの自動更新などは不要
        view.automaticallyUpdatesLighting = false
        view.rendersCameraGrain = false
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}
}
