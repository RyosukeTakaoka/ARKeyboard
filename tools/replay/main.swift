// 記録ファイルを、アプリと同じエンジンで再生するコマンド。
//
// 使い方(リポジトリのルートで):
//   swift run -c release arkeyboard-replay replay 記録.json [オプション]   → 結果の JSON を標準出力へ
//     --variant 名前            結果に付ける名前
//     --patch '{"features":{"audioOnset":false}}'   設定の上書き(JSON)
//     --noise 0.02              関節点に人工的なぶれを加える(手の大きさに対する標準偏差)
//     --seed 1                  ぶれの乱数の種
//     --corpus-dir ディレクトリ  言語モデルの学習用テキスト(既定: ARKeyboard/Resources/Corpus)
//     --dump-features           レベルB の学習用に、候補の特徴量も出す
//     --model 重み.json          レベルB の学習モデル(DenseNetwork の JSON)を使う
//
//   swift run -c release arkeyboard-replay synth --out 出力.json [オプション]   → 合成の記録を作る
//     --text "the quick brown fox"   打つ文章(既定: 練習モードのお題をつなげたもの)
//     --seed 1 --mode knee|desk --aim-noise 0.25 --interval 0.55 --false-onsets 0.3
import Foundation
@testable import ARKeyboardCore

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

var arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else {
    fail("使い方: arkeyboard-replay replay <記録.json> [オプション] / arkeyboard-replay synth --out <出力.json>")
}
arguments.removeFirst()

/// "--name 値" の形のオプションを取り出す
func option(_ name: String) -> String? {
    guard let i = arguments.firstIndex(of: name), i + 1 < arguments.count else { return nil }
    return arguments[i + 1]
}
func flag(_ name: String) -> Bool { arguments.contains(name) }

switch command {
case "replay":
    guard let path = arguments.first, !path.hasPrefix("--") else { fail("記録ファイルを指定してください") }
    guard let data = FileManager.default.contents(atPath: path) else { fail("読めません: \(path)") }
    let recording: Recording
    do { recording = try RecordingIO.load(data) } catch { fail("記録ファイルの形式が違います: \(error)") }

    var options = Replayer.Options()
    options.variantName = option("--variant") ?? "default"
    if let patch = option("--patch") {
        guard let object = try? JSONSerialization.jsonObject(with: Data(patch.utf8)) as? [String: Any] else {
            fail("--patch の JSON が読めません")
        }
        options.settingsPatch = object
    }
    options.jointNoise = Double(option("--noise") ?? "0") ?? 0
    options.noiseSeed = UInt64(option("--seed") ?? "1") ?? 1
    let corpusDir = option("--corpus-dir") ?? "ARKeyboard/Resources/Corpus"
    options.englishCorpus = try? String(contentsOfFile: corpusDir + "/corpus_english.txt", encoding: .utf8)
    options.romajiCorpus = try? String(contentsOfFile: corpusDir + "/corpus_romaji.txt", encoding: .utf8)
    options.dumpFeatures = flag("--dump-features")
    if let modelPath = option("--model") {
        guard let modelData = FileManager.default.contents(atPath: modelPath),
              let network = try? JSONDecoder().decode(DenseNetwork.self, from: modelData) else {
            fail("モデルが読めません: \(modelPath)")
        }
        options.classifier = network
    }
    let result = Replayer(recording: recording, options: options).run()
    let output = try RecordingIO.encoder().encode(result)
    FileHandle.standardOutput.write(output)
    FileHandle.standardOutput.write("\n".data(using: .utf8)!)

case "synth":
    guard let out = option("--out") else { fail("--out を指定してください") }
    let text = option("--text") ?? PracticeSession.sentences.joined(separator: " ")
    var config = SyntheticTypingConfig(targets: SyntheticRecordingGenerator.targets(from: text))
    config.seed = UInt64(option("--seed") ?? "1") ?? 1
    config.mode = KeyboardMode(rawValue: option("--mode") ?? "knee") ?? .knee
    if let v = option("--aim-noise").flatMap(Double.init) { config.aimNoise = v }
    if let v = option("--interval").flatMap(Double.init) { config.interval = v }
    if let v = option("--false-onsets").flatMap(Double.init) { config.falseOnsetRate = v }
    let recording = SyntheticRecordingGenerator.generate(config)
    do {
        try RecordingIO.encoder().encode(recording).write(to: URL(fileURLWithPath: out))
    } catch {
        fail("書き込めません: \(error)")
    }
    FileHandle.standardError.write("合成の記録を作りました: \(out)(\(config.targets.count) 文字, \(recording.frames.count) フレーム)\n".data(using: .utf8)!)

default:
    fail("知らないコマンドです: \(command)")
}
