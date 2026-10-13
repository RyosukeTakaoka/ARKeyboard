import CoreVideo

extension DepthMap {
    /// ARKit の深度バッファ(Float32、メートル)を、配列にコピーして作ります。
    ///
    /// なぜコピーするのか: CVPixelBuffer は ARKit が使い回すメモリなので、
    /// 別のスレッドで後から読むと中身が書き換わっている可能性があるためです。
    /// 256x192 程度なので、コピーしても十分速いです。
    init?(copying buffer: CVPixelBuffer) {
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_DepthFloat32 else { return nil }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }

        var values = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            // 1行の長さ(bytesPerRow)は、幅×4バイトより長いことがある(メモリの都合で余白が付く)ので、
            // 行ごとに先頭の位置を計算して読む
            let row = base.advanced(by: y * bytesPerRow).assumingMemoryBound(to: Float32.self)
            for x in 0..<width {
                values[y * width + x] = row[x]
            }
        }
        self.init(width: width, height: height, values: values)
    }
}
