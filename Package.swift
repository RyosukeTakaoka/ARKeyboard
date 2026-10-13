// swift-tools-version:5.9
//
// ⚠️ これはアプリ本体のビルド用ではありません(アプリは ARKeyboard.xcodeproj を開いてビルドします)。
//
// ARKeyboard/Core フォルダの「カメラや画面に依存しないロジック」(手の座標系・キー配置・
// キャリブレーション・タップ判定)だけを取り出して、ターミナルで単体テストするための設定です。
//
//   使い方(Mac のターミナルで、このファイルがあるフォルダに移動してから):
//     swift test
//
// iPhone が無くても、タップ判定などのロジックが意図どおり動くかを確認できます。
import PackageDescription

let package = Package(
    name: "ARKeyboardCore",
    targets: [
        .target(
            name: "ARKeyboardCore",
            path: "ARKeyboard/Core",
            // Core の型は public にしていない(アプリのコードを読みやすくするため)。
            // 再生コマンド(別モジュール)から使えるよう、リリースビルドでも @testable import を許可する
            swiftSettings: [.unsafeFlags(["-enable-testing"])]
        ),
        // 記録ファイルの再生・合成データ作り(tools/eval/ の Python から呼び出す)
        .executableTarget(
            name: "arkeyboard-replay",
            dependencies: ["ARKeyboardCore"],
            path: "tools/replay"
        ),
        .testTarget(
            name: "ARKeyboardCoreTests",
            dependencies: ["ARKeyboardCore"],
            path: "Tests/ARKeyboardCoreTests",
            // 固定データ(Python が作ったゴールデンデータ)は、テストの中でファイルとして直接読む
            exclude: ["Fixtures"]
        ),
    ]
)
