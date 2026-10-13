import Foundation
import CoreGraphics
import Vision

/// 手書きの画を、Vision の文字認識(VNRecognizeTextRequest)で文字にする。
///
/// - 認識は端末の中で行われます(Vision の文字認識はオンデバイス。画像を外部に送りません)
/// - 日本語(ja-JP)は iOS 16 以降の「正確(accurate)」モードで使えます
/// - Vision は「紙に書いた・印刷された文字の写真」向けなので、指で書いた崩れた文字は苦手です。
///   1文字〜数文字ずつ、大きめに書くと認識しやすくなります(実機で要確認)
final class HandwritingRecognizer {
    private let queue = DispatchQueue(label: "handwriting.recognition", qos: .userInitiated)

    /// 画を認識して、候補(確からしい順)を返す。completion はメインスレッドで呼ばれる
    func recognize(_ strokes: [HandwritingStroke], language: String, completion: @escaping ([String]) -> Void) {
        queue.async {
            let candidates = Self.recognizeSync(strokes, language: language)
            DispatchQueue.main.async { completion(candidates) }
        }
    }

    static func recognizeSync(_ strokes: [HandwritingStroke], language: String) -> [String] {
        let size = 160
        let pixels = HandwritingRecorder.rasterize(strokes, size: size)
        guard let image = makeImage(pixels, size: size) else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = [language]
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        // 複数の行・まとまりに分かれたら、左から(画像の中の順に)つなげる
        let observations = request.results ?? []
        var candidates: [String] = []
        if observations.count == 1, let observation = observations.first {
            candidates = observation.topCandidates(5).map(\.string)
        } else {
            let joined = observations.compactMap { $0.topCandidates(1).first?.string }.joined()
            if !joined.isEmpty { candidates = [joined] }
        }
        var seen = Set<String>()
        return candidates.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// グレースケールの画素列から CGImage を作る
    private static func makeImage(_ pixels: [UInt8], size: Int) -> CGImage? {
        let data = Data(pixels) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: size,
                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
