import Foundation

/// 1つのキー
struct Key: Identifiable, Equatable {
    /// 一意な ID(例: "left-F")
    let id: String
    /// 画面に表示する文字(例: "F")
    let label: String
    /// 入力される文字(例: "f"、スペースは " ")
    let output: String
    /// どちらの手のキーか
    let hand: Chirality
    /// 担当する指(タッチタイピングの指の割り当て)
    let finger: Finger
    /// 段: -1 = 上段(Q W E…), 0 = ホーム段(A S D…), 1 = 下段(Z X C…), 2 = スペース
    let row: Int
    /// 人差し指の内側の列(T G B / Y H N)か
    let isInnerColumn: Bool
    /// キーの中心(手の座標。x: 親指側+, y: 前+、単位は手の大きさ)
    var center: Vec2
    /// キーの大きさ(x: 横幅, y: 縦幅。手の座標の単位)
    var size: Vec2

    var isSpace: Bool { row == 2 }
}

/// 分割キーボードのキー配置を作る/指先から最も近いキーを探す。
///
/// ## 配置の考え方
/// - キーは「手の座標」(HandFrame)で表します。カメラの向きに関係なく、手の向きについてきます。
/// - ホーム段(A S D F / J K L ;)は、キャリブレーションで測った**各指先の位置そのもの**に置きます。
/// - 上段は「前(forward)」へ1行分、下段は「後ろ」へ1行分ずらします。
/// - 実物のキーボードと同じように段ごとに少し横にずれています(ロウスタッガード)。
///   ホーム段を基準に、上段は 0.25 キー左、下段は 0.5 キー右。
/// - 人差し指は2列を担当します(左手: R F V と T G B、右手: U J M と Y H N)。
///   内側の列(T G B / Y H N)は、人差し指のホーム位置から親指側に1キー分ずらします。
enum KeyLayout {
    /// 左手側の文字(上段・ホーム段・下段。キーボードの左から右の順)
    static let leftRows: [[String]] = [
        ["Q", "W", "E", "R", "T"],
        ["A", "S", "D", "F", "G"],
        ["Z", "X", "C", "V", "B"],
    ]
    /// 右手側の文字
    static let rightRows: [[String]] = [
        ["Y", "U", "I", "O", "P"],
        ["H", "J", "K", "L", ";"],
        ["N", "M", ",", "."],
    ]
    /// 列(キーボードの左から右)ごとの担当指
    static let leftColumnFingers: [Finger] = [.little, .ring, .middle, .index, .index]
    static let rightColumnFingers: [Finger] = [.index, .index, .middle, .ring, .little]

    /// 段ごとの横ずれ(キーボードの右向きを +、キー1個分を 1 とする)。上段・ホーム段・下段の順。
    static let rowStagger: [Double] = [-0.25, 0, 0.5]

    /// 見た目のすき間(キーの大きさをピッチの何割にするか)
    static let keyFillRatio = 0.9

    /// 人差し指の内側の列(T G B / Y H N)までの距離を、少しだけ遠く見積もる倍率。
    /// 例えば右手の人差し指を J から真下に動かすと、実物のキーボードと同じく N と M が
    /// ちょうど同じ距離になります。迷ったときは、よく使うホーム側の列(M)を選ぶようにするためです。
    static let innerColumnPenalty = 1.1

    /// 人差し指の「内側の列」か(左手の T G B、右手の Y H N)
    static func isInnerIndexColumn(hand: Chirality, column: Int) -> Bool {
        hand == .left ? column == 4 : column == 0
    }

    /// キャリブレーション結果から、片手分のキーを作ります。
    /// - Parameter keyScale: キーの大きさの倍率(膝モードは少し大きめにする等)
    static func makeKeys(for calibration: HandCalibration, keyScale: Double) -> [Key] {
        let hand = calibration.chirality
        let pitch = calibration.keyPitch * keyScale
        let rowPitch = calibration.rowPitch * keyScale
        // 「キーボードの右」は、左手では親指側(+x)、右手では小指側(−x)
        let keyboardRight: Double = hand == .left ? 1 : -1
        let rows = hand == .left ? leftRows : rightRows
        let columnFingers = hand == .left ? leftColumnFingers : rightColumnFingers

        var keys: [Key] = []
        for (rowIndex, labels) in rows.enumerated() {
            let row = rowIndex - 1  // -1, 0, 1
            for (column, label) in labels.enumerated() {
                let finger = columnFingers[column]
                guard let home = calibration.homeTips[finger] else { continue }
                var center = home
                let isInner = isInnerIndexColumn(hand: hand, column: column)
                if isInner {
                    center.x += pitch  // 親指側に1キー分
                }
                center.y -= Double(row) * rowPitch  // 上段(row = -1)は前へ
                center.x += keyboardRight * rowStagger[rowIndex] * pitch
                keys.append(Key(id: "\(hand.rawValue)-\(label)",
                                label: label,
                                output: label.lowercased(),
                                hand: hand,
                                finger: finger,
                                row: row,
                                isInnerColumn: isInner,
                                center: center,
                                size: Vec2(pitch * keyFillRatio, rowPitch * keyFillRatio)))
            }
        }

        // スペースキー(親指)。親指のホーム位置を中心に、キーボードの中央側へ少し寄せて横長に置く。
        if let thumb = calibration.homeTips[.thumb] {
            keys.append(Key(id: "\(hand.rawValue)-space",
                            label: "space",
                            output: " ",
                            hand: hand,
                            finger: .thumb,
                            row: 2,
                            isInnerColumn: false,
                            center: thumb + Vec2(pitch * 0.5, 0),
                            size: Vec2(pitch * 3, rowPitch * keyFillRatio)))
        }
        return keys
    }

    /// 指先(手の座標)に最も近いキーを探します。
    ///
    /// - Parameters:
    ///   - point: 指先の位置(手の座標)
    ///   - finger: どの指か
    ///   - keys: 片手分のキー
    ///   - restrictToFinger: true なら、その指の担当キーだけから探す
    ///     (例: 中指なら E D C だけ)。カメラの誤差で隣のキーに化けるのを大きく減らせます。
    ///     親指は常にスペースだけです。
    ///   - maxDistance: これより遠いキーは「押していない」とみなす(キーの大きさ単位)
    /// - Returns: 見つかったキーと、その距離(キーの大きさ単位)
    static func nearestKey(to point: Vec2,
                           finger: Finger,
                           in keys: [Key],
                           restrictToFinger: Bool,
                           maxDistance: Double) -> (key: Key, distance: Double)? {
        var best: (key: Key, distance: Double)?
        for key in keys {
            // 親指はスペースだけ、他の指はスペース以外
            if (finger == .thumb) != key.isSpace { continue }
            if restrictToFinger && finger != .thumb && key.finger != finger { continue }
            // キーの縦横の大きさで割った距離(楕円形の距離)。
            // 縦長・横長のキーでも「キー何個分離れているか」で比べられる。
            let d = point - key.center
            var distance = Vec2(d.x / max(key.size.x, 1e-6), d.y / max(key.size.y, 1e-6)).length
            if key.isInnerColumn { distance *= innerColumnPenalty }
            if distance <= maxDistance, distance < (best?.distance ?? .infinity) {
                best = (key, distance)
            }
        }
        return best
    }
}
