import Foundation

/// 「下向き」をどの向きとみなすか
enum TapDirection: String, Codable, CaseIterable, Identifiable {
    /// 手首の方向(手の座標系の「後ろ」)。
    /// iPhone を手の上にかざして見下ろす置き方では、指を下ろすと指先は手首側へ動いて見えます
    /// (指が曲がって短く見える + 遠ざかるので画面の手前側に寄る)。カメラの回転に影響されません。
    case towardWrist
    /// 画面(画像)の下方向。正面やや上から撮るなど、手首の方向とずれる置き方のとき用。
    case imageDown
    /// 向きを問わず「速く動いて急に止まった」ものをタップとする(指を上げる動きも拾いやすい)。
    case anyDirection

    var id: String { rawValue }

    var japaneseName: String {
        switch self {
        case .towardWrist: return "手首の方向(上から撮影)"
        case .imageDown: return "画面の下方向"
        case .anyDirection: return "向きを問わない"
        }
    }
}

/// タップ判定のしきい値。単位の「手」は「手首〜中指の付け根の長さ」(約9cm)です。
struct TapParameters: Codable, Equatable {
    /// 下向きの速さがこれを超えたら「下ろし始めた」とみなす(手/秒)。小さいほど敏感。
    var downSpeed: Double = 1.2
    /// 速さがピークのこの割合以下に落ちたら「止まった(=面に当たった)」とみなす(0〜1)。
    /// 大きいほど、ゆっくりした止まり方でもタップになる(敏感)。
    var stopRatio: Double = 0.35
    /// 下ろし始めてから止まるまでに、これ以上動いていないとタップにしない(手)。手ぶれ対策。
    var minTravel: Double = 0.06
    /// 下ろし始めてからこれ以上たっても止まらなければ、タップではない(ゆっくりした動き)(秒)
    var maxDownDuration: Double = 0.25
    /// 同じ指の連続誤検出を防ぐ待ち時間(秒)
    var cooldown: Double = 0.15
    /// 手全体がこれより速く動いているときは、タップ判定しない(手/秒)。手を移動させている最中の誤検出対策。
    var maxPalmSpeed: Double = 1.5
    /// 位置の平滑化(0 = しない 〜 0.9 = 強く)。大きいほど震えに強いが、止まりの検出が遅れる。
    var smoothing: Double = 0.3
    /// 同じ手の別の指が直前にタップしていたら、この時間はタップにしない(秒)。
    /// 1本の指を下ろすと隣の指もつられて動くため。
    var sameHandLockout: Double = 0.06
    /// 「下向き」の定義
    var direction: TapDirection = .towardWrist
}

/// 検出したタップ
struct TapEvent: Equatable {
    var finger: FingerID
    /// タップした(止まった)時刻
    var timestamp: Double
    /// 止まった瞬間の指先の位置(画像のピクセル座標)。この位置でキーを決める。
    var tipPosition: Vec2
    /// 下ろしたときの最大の速さ(手/秒)
    var peakSpeed: Double
    /// 下ろした距離(手)
    var travel: Double
}

/// デバッグ用のグラフに出す、1本の指の1フレーム分の値
struct FingerSignalSample: Equatable {
    var timestamp: Double
    /// 下向きの速さ(手/秒)。上向きはマイナス。
    var speed: Double
    /// その時点のしきい値(感度を反映済み)
    var threshold: Double
    /// 「下ろしている途中」か
    var isDescending: Bool
    /// このフレームでタップと判定されたか
    var didTap: Bool
}

/// 指ごとの速度から「タップした瞬間」を見つけるクラス。
///
/// ## 判定の流れ(指1本ごと)
/// ```
///  [待機] ──下向きの速さ ≥ しきい値──▶ [下降中] ──速さ ≤ ピーク×stopRatio(急減速・反転)──▶ タップ!
///    ▲                                   │                     (ただし移動量 ≥ minTravel のとき)
///    └──── maxDownDuration を超えた / 手全体が動いた ─┘
/// ```
/// ## 手全体の動きを打ち消す
/// 指先の位置そのものではなく、「指先 − 手のひらの中心」(手のひらに対する相対位置)を使います。
/// 手ごと動かしても相対位置は変わらないので、タップと誤検出しません。
/// さらに手の大きさで割るので、カメラに近づいても遠ざかっても同じしきい値で判定できます。
final class TapDetector {
    var parameters: TapParameters
    /// 感度(0〜1)。0.5 が標準。大きいほど小さく遅いタップでも反応する。
    var sensitivity: Double = 0.5
    /// これより信頼度の低い点は無視する
    var minConfidence: Double = 0.3

    /// 指先が途切れた(見えなかった)時間がこれを超えたら、速度の計算をやり直す(秒)
    private let maxFrameGap = 0.2

    private enum Phase {
        case idle
        case descending(startTime: Double, startSignal: Double, startRel: Vec2, peak: Double)
    }

    private struct FingerState {
        var lastTime: Double
        /// 下向きの量(平滑化済み、手の単位)
        var signal: Double
        /// 手のひらに対する指先の位置(平滑化済み、手の単位)
        var rel: Vec2
        /// 指が最後に「ほぼ止まっていた」ときの値。移動量はここから測る
        /// (しきい値を超えたフレームから測ると、動き出しの分が抜けて小さく見積もってしまうため)
        var restSignal: Double
        var restRel: Vec2
        var phase: Phase = .idle
    }

    private struct PalmState {
        var lastTime: Double
        var center: Vec2
        var speed: Double
    }

    private var fingers: [FingerID: FingerState] = [:]
    private var palms: [Chirality: PalmState] = [:]
    /// 指ごとの「この時刻まではタップにしない」
    private var cooldownUntil: [FingerID: Double] = [:]
    /// 手ごとの最後のタップ時刻
    private var lastTapTime: [Chirality: Double] = [:]

    init(parameters: TapParameters = TapParameters()) {
        self.parameters = parameters
    }

    /// 感度による倍率。感度 0 → 2倍(鈍い)、0.5 → 1倍、1 → 0.5倍(敏感)
    var thresholdFactor: Double {
        pow(2, (0.5 - min(max(sensitivity, 0), 1)) * 2)
    }

    /// 感度を反映した速さのしきい値(手/秒)
    var effectiveDownSpeed: Double { parameters.downSpeed * thresholdFactor }
    /// 感度を反映した移動量のしきい値(手)
    var effectiveMinTravel: Double { parameters.minTravel * thresholdFactor }

    func reset() {
        fingers.removeAll()
        palms.removeAll()
        cooldownUntil.removeAll()
        lastTapTime.removeAll()
    }

    /// 手のひらの中心 = 手首と4本の指の付け根の平均(見えている点だけ)。
    /// 1点だけより、複数の点の平均の方がノイズに強い。
    static func palmCenter(of hand: HandObservation, minConfidence: Double) -> Vec2? {
        let joints: [Joint] = [.wrist, .indexMCP, .middleMCP, .ringMCP, .littleMCP]
        let points = joints.compactMap { hand.position($0, minConfidence: minConfidence) }
        guard points.count >= 2 else { return nil }
        return Vec2.average(points)
    }

    /// 1フレーム分を処理して、このフレームで起きたタップを返します。
    /// - Parameters:
    ///   - hands: 手ごとの (観測, 手の座標系)。座標系は「下向き」と「手の大きさ」を知るために使う。
    ///   - timestamp: 撮影時刻(秒)
    ///   - observedFinger: デバッググラフ用に値を取り出したい指
    func process(hands: [Chirality: (observation: HandObservation, frame: HandFrame)],
                 timestamp: Double,
                 observedFinger: FingerID? = nil) -> (taps: [TapEvent], sample: FingerSignalSample?) {
        var taps: [TapEvent] = []
        var sample: FingerSignalSample?
        let threshold = effectiveDownSpeed
        let minTravel = effectiveMinTravel
        let smoothingAlpha = 1 - min(max(parameters.smoothing, 0), 0.95)

        for chirality in Chirality.allCases {
            guard let (hand, frame) = hands[chirality],
                  let palm = Self.palmCenter(of: hand, minConfidence: minConfidence) else {
                // 手が見えない → この手の状態を捨てる(次に見えたとき、離れた位置から急に速度が出ないように)
                palms[chirality] = nil
                for finger in Finger.allCases { fingers[FingerID(chirality: chirality, finger: finger)] = nil }
                continue
            }

            // 手全体の速さ(手/秒)
            var handIsMoving = false
            if let previous = palms[chirality], timestamp > previous.lastTime,
               timestamp - previous.lastTime <= maxFrameGap {
                let raw = previous.center.distance(to: palm) / frame.scale / (timestamp - previous.lastTime)
                // 1フレームだけの跳ねを抑えるため、少しだけ平滑化する
                let speed = previous.speed + (raw - previous.speed) * 0.6
                palms[chirality] = PalmState(lastTime: timestamp, center: palm, speed: speed)
                handIsMoving = speed > parameters.maxPalmSpeed
            } else {
                palms[chirality] = PalmState(lastTime: timestamp, center: palm, speed: 0)
            }

            // このフレームでタップ候補になった指(後で1本に絞る)
            var candidates: [TapEvent] = []

            for finger in Finger.allCases {
                let id = FingerID(chirality: chirality, finger: finger)
                guard let tip = hand.position(Joint.tip(of: finger), minConfidence: minConfidence) else {
                    // 信頼度の低い点は無視する(位置がデタラメなことが多い)
                    fingers[id] = nil
                    continue
                }

                // 手のひらに対する相対位置(手の単位)
                let rel = (tip - palm) / frame.scale
                // 「下向きにどれだけ進んでいるか」を1つの数値にする
                let rawSignal: Double
                switch parameters.direction {
                case .towardWrist: rawSignal = -rel.dot(frame.forward)  // 手首の方向が +
                case .imageDown: rawSignal = rel.y                       // 画像の下が +(y は下向きが正)
                case .anyDirection: rawSignal = 0                        // 速さはベクトルの長さで別に計算
                }

                guard var state = fingers[id], timestamp > state.lastTime,
                      timestamp - state.lastTime <= maxFrameGap else {
                    // 初めて見えた/しばらく途切れていた → 基準を作り直すだけ
                    fingers[id] = FingerState(lastTime: timestamp, signal: rawSignal, rel: rel,
                                              restSignal: rawSignal, restRel: rel)
                    continue
                }

                let dt = timestamp - state.lastTime
                let previousSignal = state.signal
                let previousRel = state.rel
                // 平滑化(前の値から新しい値へ alpha の割合だけ近づける=指数移動平均)
                state.signal = previousSignal + (rawSignal - previousSignal) * smoothingAlpha
                state.rel = previousRel + (rel - previousRel) * smoothingAlpha
                state.lastTime = timestamp

                // 下向きの速さ(手/秒)
                let speed: Double
                if parameters.direction == .anyDirection {
                    speed = (state.rel - previousRel).length / dt
                } else {
                    speed = (state.signal - previousSignal) / dt
                }

                switch state.phase {
                case .idle:
                    let cooledDown = timestamp >= (cooldownUntil[id] ?? -Double.infinity)
                    if !handIsMoving && cooledDown && speed >= threshold {
                        // 下ろし始めた。始点は「最後に止まっていたとき」の値にしておく
                        state.phase = .descending(startTime: timestamp - dt, startSignal: state.restSignal,
                                                  startRel: state.restRel, peak: speed)
                    } else if abs(speed) < threshold * 0.3 {
                        // ほぼ止まっている → ここを次の動きの始点の候補にする
                        state.restSignal = state.signal
                        state.restRel = state.rel
                    }

                case .descending(let startTime, let startSignal, let startRel, let peak):
                    if handIsMoving {
                        state.phase = .idle
                    } else if speed <= peak * parameters.stopRatio {
                        // 急に減速した(または上向きに反転した)= 面に当たった瞬間
                        let travel: Double
                        if parameters.direction == .anyDirection {
                            travel = max((state.rel - startRel).length, (previousRel - startRel).length)
                        } else {
                            travel = max(state.signal, previousSignal) - startSignal
                        }
                        if travel >= minTravel {
                            candidates.append(TapEvent(finger: id, timestamp: timestamp, tipPosition: tip,
                                                       peakSpeed: peak, travel: travel))
                        }
                        state.phase = .idle
                        state.restSignal = state.signal
                        state.restRel = state.rel
                    } else if timestamp - startTime > parameters.maxDownDuration {
                        // ゆっくりすぎる動きはタップではない
                        state.phase = .idle
                    } else {
                        state.phase = .descending(startTime: startTime, startSignal: startSignal,
                                                  startRel: startRel, peak: max(peak, speed))
                    }
                }
                fingers[id] = state

                if id == observedFinger {
                    var isDescending = false
                    if case .descending = state.phase { isDescending = true }
                    sample = FingerSignalSample(timestamp: timestamp, speed: speed, threshold: threshold,
                                                isDescending: isDescending, didTap: false)
                }
            }

            // 同じ手で同時に複数の指が候補になったら、いちばん勢いのある指だけを採用する
            // (1本の指を下ろすと、隣の指もつられて少し動くため)
            guard let best = candidates.max(by: { $0.peakSpeed < $1.peakSpeed }) else { continue }
            if let last = lastTapTime[chirality], timestamp - last < parameters.sameHandLockout {
                continue
            }
            taps.append(best)
            cooldownUntil[best.finger] = timestamp + parameters.cooldown
            lastTapTime[chirality] = timestamp
            if best.finger == observedFinger {
                sample?.didTap = true
            }
        }
        return (taps, sample)
    }
}
