import Foundation

/// 「項目が足りない JSON」でも読み込めるようにするための道具。
///
/// アプリを更新して設定の項目が増えると、古い保存データ(や古い記録ファイル)には新しい項目が無いので、
/// Swift の標準の読み込み(Codable)は失敗してしまいます。
/// そこで「初期値を JSON にしたもの」に「保存データの JSON」を重ねてから読みます。
/// 保存データにある項目は保存データの値、無い項目は初期値になります。
enum TolerantDecoding {
    /// 辞書を重ねる(入れ子の辞書は中まで重ねる)
    static func merge(_ base: [String: Any], _ overlay: [String: Any]) -> [String: Any] {
        var result = base
        for (key, value) in overlay {
            if let baseChild = base[key] as? [String: Any], let overlayChild = value as? [String: Any] {
                result[key] = merge(baseChild, overlayChild)
            } else {
                result[key] = value
            }
        }
        return result
    }

    /// 初期値に重ねて読み込む
    static func decode<T: Codable>(_ type: T.Type, from data: Data, defaults: T,
                                   decoder: JSONDecoder = JSONDecoder(),
                                   encoder: JSONEncoder = JSONEncoder()) -> T? {
        guard let defaultData = try? encoder.encode(defaults),
              let base = try? JSONSerialization.jsonObject(with: defaultData) as? [String: Any],
              let saved = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let merged = try? JSONSerialization.data(withJSONObject: merge(base, saved)) else {
            return nil
        }
        return try? decoder.decode(T.self, from: merged)
    }
}

extension RecordingIO {
    /// 記録ファイルを読む。設定の項目が足りない古いファイルでも読めるように、設定だけは初期値に重ねる。
    static func load(_ data: Data) throws -> Recording {
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RecordingError.invalidFormat
        }
        guard object["format"] as? String == Recording.formatName else { throw RecordingError.invalidFormat }
        if let settings = object["settings"] as? [String: Any],
           let defaultsData = try? encoder().encode(KeyboardSettings()),
           let defaults = try? JSONSerialization.jsonObject(with: defaultsData) as? [String: Any] {
            object["settings"] = TolerantDecoding.merge(defaults, settings)
        }
        let merged = try JSONSerialization.data(withJSONObject: object)
        return try decoder().decode(Recording.self, from: merged)
    }

    enum RecordingError: Error {
        case invalidFormat
    }
}
