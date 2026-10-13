import SwiftUI

/// カメラが使えないときに、理由と対処法を表示する View。
/// シミュレーターではカメラが無いので、ここで「実機で実行してください」と表示します。
struct CameraStatusView: View {
    let status: CameraStatus

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: iconName)
                .font(.system(size: 48))
            Text(title)
                .font(.title3.bold())
            Text(message)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if status == .denied {
                // 一度「許可しない」を選ぶと、アプリからは再度ダイアログを出せません。
                // そのため「設定」アプリの、このアプリのページを開くボタンを用意します。
                Button("設定アプリを開く") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    private var iconName: String {
        switch status {
        case .unavailable: return "iphone.slash"
        case .denied: return "video.slash"
        case .failed: return "exclamationmark.triangle"
        case .idle, .running: return "camera"
        }
    }

    private var title: String {
        switch status {
        case .unavailable: return "実機で実行してください"
        case .denied: return "カメラへのアクセスが許可されていません"
        case .failed: return "カメラを開始できませんでした"
        case .idle, .running: return "カメラを準備しています…"
        }
    }

    private var message: String {
        switch status {
        case .unavailable:
            return "このアプリは背面カメラで手を認識します。\nシミュレーターにはカメラが無いため動作しません。\niPhone 実機を接続して実行してください。"
        case .denied:
            return "設定アプリ → ARKeyboard → カメラ をオンにしてください。"
        case .failed(let reason):
            return reason
        case .idle, .running:
            return ""
        }
    }
}
