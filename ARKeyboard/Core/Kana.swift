import Foundation

/// フリックの方向(5クラス)。「段」に対応する
enum FlickDirection: Int, Codable, CaseIterable, Identifiable {
    /// タップ(動かさない)= あ段
    case tap = 0
    /// 左 = い段
    case left = 1
    /// 上 = う段
    case up = 2
    /// 右 = え段
    case right = 3
    /// 下 = お段
    case down = 4

    var id: Int { rawValue }

    var japaneseName: String {
        switch self {
        case .tap: return "タップ"
        case .left: return "左"
        case .up: return "上"
        case .right: return "右"
        case .down: return "下"
        }
    }

    /// 画面で見たときの向き(ラジアン。右 = 0、上 = π/2)。タップは向きを持たない
    var angle: Double? {
        switch self {
        case .tap: return nil
        case .right: return 0
        case .up: return Double.pi / 2
        case .left: return Double.pi
        case .down: return -Double.pi / 2
        }
    }
}

/// フリックパッドの1つのキー(12個のうち1つ)
struct FlickKeyDefinition: Equatable {
    /// 表示名(例: "あ")
    var label: String
    /// 方向ごとの入力(タップ, 左, 上, 右, 下)。無い方向は nil
    var outputs: [String?]
    /// 濁点・小文字の切り替えキーか
    var isModifier: Bool = false

    func output(for direction: FlickDirection) -> String? {
        direction.rawValue < outputs.count ? outputs[direction.rawValue] : nil
    }
}

/// 日本語の 12 キーのフリック配置(iPhone の「日本語かな」とほぼ同じ)
enum FlickLayout {
    /// 4段 × 3列。上の段から、キーボードの左から右へ
    static let rows: [[FlickKeyDefinition]] = [
        [k("あ", "あいうえお"), k("か", "かきくけこ"), k("さ", "さしすせそ")],
        [k("た", "たちつてと"), k("な", "なにぬねの"), k("は", "はひふへほ")],
        [k("ま", "まみむめも"), FlickKeyDefinition(label: "や", outputs: ["や", "「", "ゆ", "」", "よ"]), k("ら", "らりるれろ")],
        [FlickKeyDefinition(label: "゛゜小", outputs: ["゛", nil, nil, nil, nil], isModifier: true),
         FlickKeyDefinition(label: "わ", outputs: ["わ", "を", "ん", "ー", nil]),
         FlickKeyDefinition(label: "、。", outputs: ["、", "。", "?", "!", nil])],
    ]

    private static func k(_ label: String, _ five: String) -> FlickKeyDefinition {
        FlickKeyDefinition(label: label, outputs: five.map { String($0) })
    }

    /// すべてのキー(段, 列, 定義)
    static var allKeys: [(row: Int, column: Int, definition: FlickKeyDefinition)] {
        rows.enumerated().flatMap { r, row in row.enumerated().map { (r, $0.offset, $0.element) } }
    }

    /// 仮名 → (段, 列, 方向)。評価ツールで「どのキーのどの方向が正解か」を知るため
    static func position(of kana: String) -> (row: Int, column: Int, direction: FlickDirection)? {
        for entry in allKeys {
            for direction in FlickDirection.allCases where entry.definition.output(for: direction) == kana {
                return (entry.row, entry.column, direction)
            }
        }
        // 濁点・半濁点・小文字は、元の仮名の位置(+ 機能キー)
        if let base = KanaModifier.base(of: kana) { return position(of: base) }
        return nil
    }

    /// 仮名の言語モデルで使う文字(フリックで出せる文字すべて + 濁点などの付いた文字)
    static var kanaVocabulary: [Character] {
        var set: [Character] = []
        for entry in allKeys where !entry.definition.isModifier {
            for case let s? in entry.definition.outputs where s.count == 1 {
                let c = Character(s)
                if !set.contains(c) { set.append(c) }
            }
        }
        for c in KanaModifier.allVariants where !set.contains(c) { set.append(c) }
        return set
    }
}

/// 「゛゜小」キー: 直前の仮名を、濁点 → 半濁点 → 小文字 → 元 の順に切り替える
enum KanaModifier {
    /// 切り替えの順番(元の文字から始まる輪)
    private static let cycles: [[Character]] = {
        var list: [[Character]] = []
        let dakuten: [(Character, Character)] = [
            ("か", "が"), ("き", "ぎ"), ("く", "ぐ"), ("け", "げ"), ("こ", "ご"),
            ("さ", "ざ"), ("し", "じ"), ("す", "ず"), ("せ", "ぜ"), ("そ", "ぞ"),
            ("た", "だ"), ("ち", "ぢ"), ("て", "で"), ("と", "ど"),
        ]
        for (a, b) in dakuten { list.append([a, b]) }
        list.append(["つ", "っ", "づ"])
        for (a, b, c) in [("は", "ば", "ぱ"), ("ひ", "び", "ぴ"), ("ふ", "ぶ", "ぷ"), ("へ", "べ", "ぺ"), ("ほ", "ぼ", "ぽ")] as [(Character, Character, Character)] {
            list.append([a, b, c])
        }
        for (a, b) in [("あ", "ぁ"), ("い", "ぃ"), ("え", "ぇ"), ("お", "ぉ"), ("や", "ゃ"), ("ゆ", "ゅ"), ("よ", "ょ"), ("わ", "ゎ")] as [(Character, Character)] {
            list.append([a, b])
        }
        list.append(["う", "ぅ", "ゔ"])
        return list
    }()

    /// 次の形(切り替えられない文字なら nil)
    static func cycle(_ c: Character) -> Character? {
        for cycle in cycles {
            if let i = cycle.firstIndex(of: c) { return cycle[(i + 1) % cycle.count] }
        }
        return nil
    }

    /// 濁点などを外した元の文字
    static func base(of s: String) -> String? {
        guard s.count == 1, let c = s.first else { return nil }
        for cycle in cycles where cycle.dropFirst().contains(c) { return String(cycle[0]) }
        return nil
    }

    static var allVariants: [Character] { cycles.flatMap { $0 } }
}
