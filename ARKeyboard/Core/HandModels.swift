import Foundation

// このファイルには「手」を表すデータの型をまとめています。
// Vision フレームワークの型(VNHumanHandPoseObservation など)を、アプリ内では直接使わずに
// ここで定義した型に変換してから使います。理由は次の2つです。
//  1. Vision の座標(原点が左下・0〜1に正規化)を、変換の入り口1か所で「画像のピクセル座標
//     (原点が左上)」に統一できる。後のコードで座標系を取り違える事故が減る。
//  2. Vision に依存しないので、キャリブレーションやタップ判定を単体テストできる。

/// 左手か右手か(Vision の「chirality(キラリティ=左右の利き)」に対応)
enum Chirality: String, Codable, CaseIterable, Hashable, Identifiable {
    case left
    case right

    var id: String { rawValue }

    var japaneseName: String {
        switch self {
        case .left: return "左手"
        case .right: return "右手"
        }
    }

    /// 反対の手
    var opposite: Chirality {
        switch self {
        case .left: return .right
        case .right: return .left
        }
    }
}

/// 指の種類
enum Finger: String, Codable, CaseIterable, Hashable, Identifiable {
    case thumb   // 親指
    case index   // 人差し指
    case middle  // 中指
    case ring    // 薬指
    case little  // 小指

    var id: String { rawValue }

    var japaneseName: String {
        switch self {
        case .thumb: return "親指"
        case .index: return "人差し指"
        case .middle: return "中指"
        case .ring: return "薬指"
        case .little: return "小指"
        }
    }

    /// 親指以外の4本(キーボードの文字キーを担当する指)
    static let typingFingers: [Finger] = [.index, .middle, .ring, .little]
}

/// 「どちらの手の、どの指か」をまとめた識別子
struct FingerID: Hashable, Codable, Identifiable {
    var chirality: Chirality
    var finger: Finger

    var id: String { "\(chirality.rawValue)-\(finger.rawValue)" }

    var japaneseName: String { "\(chirality.japaneseName)の\(finger.japaneseName)" }

    /// 全10本
    static let all: [FingerID] = Chirality.allCases.flatMap { hand in
        Finger.allCases.map { FingerID(chirality: hand, finger: $0) }
    }
}

/// 手の関節点(Vision の VNHumanHandPoseObservation.JointName に1対1で対応する21点)。
///
/// 指の関節の名前(付け根から指先へ):
/// - 親指: CMC(手首寄りの付け根)→ MP → IP → Tip(指先)
/// - 他の指: MCP(付け根=こぶし)→ PIP → DIP → Tip(指先)
enum Joint: String, CaseIterable, Codable, Hashable {
    case wrist
    case thumbCMC, thumbMP, thumbIP, thumbTip
    case indexMCP, indexPIP, indexDIP, indexTip
    case middleMCP, middlePIP, middleDIP, middleTip
    case ringMCP, ringPIP, ringDIP, ringTip
    case littleMCP, littlePIP, littleDIP, littleTip

    /// 指先
    static func tip(of finger: Finger) -> Joint {
        switch finger {
        case .thumb: return .thumbTip
        case .index: return .indexTip
        case .middle: return .middleTip
        case .ring: return .ringTip
        case .little: return .littleTip
        }
    }

    /// 指先の1つ手前の関節(指の向きを知るのに使う)
    static func dip(of finger: Finger) -> Joint {
        switch finger {
        case .thumb: return .thumbIP
        case .index: return .indexDIP
        case .middle: return .middleDIP
        case .ring: return .ringDIP
        case .little: return .littleDIP
        }
    }

    /// 指の付け根(こぶし)。親指は MP 関節を使います。
    static func knuckle(of finger: Finger) -> Joint {
        switch finger {
        case .thumb: return .thumbMP
        case .index: return .indexMCP
        case .middle: return .middleMCP
        case .ring: return .ringMCP
        case .little: return .littleMCP
        }
    }

    /// 指の骨格を線で描くときの順番(付け根→指先)
    static func chain(of finger: Finger) -> [Joint] {
        switch finger {
        case .thumb: return [.wrist, .thumbCMC, .thumbMP, .thumbIP, .thumbTip]
        case .index: return [.wrist, .indexMCP, .indexPIP, .indexDIP, .indexTip]
        case .middle: return [.wrist, .middleMCP, .middlePIP, .middleDIP, .middleTip]
        case .ring: return [.wrist, .ringMCP, .ringPIP, .ringDIP, .ringTip]
        case .little: return [.wrist, .littleMCP, .littlePIP, .littleDIP, .littleTip]
        }
    }
}

/// 1つの関節点
struct JointPoint: Equatable {
    /// 画像上の位置(ピクセル単位、原点は画像の左上、y は下向きが正)
    var position: Vec2
    /// 信頼度(0〜1)。Vision が「この点にどれくらい自信があるか」。手が隠れていると低くなります。
    var confidence: Double
}

/// 1フレームで検出された1つの手
struct HandObservation: Equatable {
    /// Vision が判定した左右。判定できなかったときは nil。
    var chirality: Chirality?
    /// 関節点(検出できなかった関節は入っていない)
    var joints: [Joint: JointPoint]

    /// 信頼度がしきい値以上のときだけ位置を返します。
    /// 信頼度の低い点は位置がデタラメなことが多いので、使わないようにするためです。
    func position(_ joint: Joint, minConfidence: Double) -> Vec2? {
        guard let point = joints[joint], point.confidence >= minConfidence else { return nil }
        return point.position
    }
}

/// カメラ1コマ分の「手の認識結果」。HandPoseDetector が作り、ViewModel に渡します。
struct VisionFrame {
    /// 撮影時刻(秒)。速度の計算に使うので、処理した時刻ではなく「撮影した時刻」を使います。
    var timestamp: Double
    /// 向きを補正した後の画像サイズ(ピクセル)。縦向きなら 720 x 1280 のように縦長になります。
    var imageSize: Vec2
    /// 検出された手(0〜2個)
    var hands: [HandObservation]
    /// LiDAR の深度マップ(LiDAR モードのときだけ。それ以外は nil)
    var depthMap: DepthMap? = nil
}
