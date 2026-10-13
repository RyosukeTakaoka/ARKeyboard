import SwiftUI

/// 画面上部の入力結果の表示と、バックスペース・改行・クリアのボタン。
struct TextDisplayView: View {
    let text: String
    let onBackspace: () -> Void
    let onNewline: () -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // ScrollViewReader で、文字が増えたら自動で一番下までスクロールする
            ScrollViewReader { proxy in
                ScrollView {
                    // 末尾の「|」はカーソルの代わり。空白も見えるようにするため。
                    Text(text.isEmpty ? "ここに入力した文字が表示されます" : text + "|")
                        .font(.system(.title3, design: .monospaced))
                        .foregroundStyle(text.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id("end")
                }
                .frame(height: 84)
                .onChange(of: text) { _, _ in
                    proxy.scrollTo("end", anchor: .bottom)
                }
            }

            HStack {
                Button(action: onBackspace) {
                    Label("削除", systemImage: "delete.left")
                }
                Button(action: onNewline) {
                    Label("改行", systemImage: "return")
                }
                Spacer()
                Button(role: .destructive, action: onClear) {
                    Label("クリア", systemImage: "trash")
                }
            }
            .buttonStyle(.bordered)
            .labelStyle(.titleAndIcon)
            .font(.callout)
        }
        .padding(12)
        // .regularMaterial は「すりガラス」風の背景。カメラ映像の上でも文字が読みやすい。
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
    }
}
