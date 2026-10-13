import Foundation

/// センサー融合の設定(時間窓など)
struct FusionConfig: Codable, Equatable {
    /// カメラのタップ時刻より「前」に、どこまでの音を対応づけるか(秒)。
    /// カメラは「止まったコマ」でタップと判定するので、実際に当たったのはそれより少し前になる。
    var windowBefore: Double = 0.10
    /// カメラのタップ時刻より「後」に、どこまでの音を対応づけるか(秒)
    var windowAfter: Double = 0.06
    /// 音のデータが遅れていても、これ以上は待たない(秒)。待ちすぎると入力が遅れて感じるため
    var maxWait: Double = 0.4
    /// センサーから最後にデータが届いてからこれ以上たったら、そのセンサーは止まっているとみなす(秒)
    var staleAfter: Double = 0.6
    /// 自分で鳴らしたクリック音・触覚の振動を拾わないよう、フィードバック直後に無視する時間(秒)
    var feedbackMute: Double = 0.12
}

/// カメラのタップ候補と、音・振動のオンセットを突き合わせる(タップ推定レベルA の後半)。
///
/// ## 二重条件(Acustico の考え方を iPhone 向けにしたもの)
/// カメラで「指が下りて急停止した」候補が出ても、すぐには確定せず保留します。
/// その時刻の前後(windowBefore〜windowAfter)に、マイクの音の立ち上がり(または本体の振動)があれば確定。
/// その時刻までのデータが届いたのに何も無ければ却下(空中で指を止めただけ、など)。
///
/// ```
///   時間 →        [ windowBefore | windowAfter ]
///   カメラ候補 ─────────────────▲(止まったコマ)
///   音          ─────────────●─────────────   ● が窓の中なら採用
/// ```
/// マイクも加速度センサーも動いていない(許可されていない等)ときは、入力が止まらないように
/// カメラだけで確定します(メモ付き)。
///
/// Payload は「候補に付けておく情報」(エンジンが作る TouchEvent など)。中身はこのクラスでは見ません。
final class SensorFusion<Payload> {
    struct Decision {
        var payload: Payload
        /// カメラのタップ時刻
        var time: Double
        /// 対応づけた音のオンセット
        var audio: OnsetEvent?
        /// 対応づけた振動のオンセット
        var motion: OnsetEvent?
        var accepted: Bool
        var note: String?
    }

    var config = FusionConfig()
    /// 音のオンセットを条件に使うか
    var useAudio = true
    /// 振動のオンセットも「当たった証拠」として使うか(音か振動のどちらかがあれば採用)
    var useMotion = false

    private var pending: [(time: Double, payload: Payload)] = []
    private var onsets: [OnsetEvent] = []
    /// 各センサーのデータを、どの時刻まで解析し終えたか
    private var coveredUntil: [OnsetEvent.Source: Double] = [:]
    /// 各センサーから最後にデータが届いた時刻(「今」の基準)
    private var lastReceived: [OnsetEvent.Source: Double] = [:]
    /// 自分のフィードバックの音・振動を無視する時間帯
    private var muteIntervals: [(start: Double, end: Double)] = []

    init() {}

    func reset() {
        pending.removeAll()
        onsets.removeAll()
        coveredUntil.removeAll()
        lastReceived.removeAll()
        muteIntervals.removeAll()
    }

    /// 保留中の候補の数(デバッグ用)
    var pendingCount: Int { pending.count }

    /// カメラのタップ候補を追加する
    func addCandidate(time: Double, payload: Payload) {
        pending.append((time, payload))
    }

    /// 音・振動のオンセットを追加する
    /// - Parameters:
    ///   - events: 新しく見つかったオンセット
    ///   - source: どのセンサーか
    ///   - coveredUntil: このセンサーのデータを、どの時刻まで解析し終えたか
    ///   - now: 今の時刻(届いた時刻)
    func addOnsets(_ events: [OnsetEvent], source: OnsetEvent.Source, coveredUntil time: Double, now: Double) {
        for event in events where !isMuted(event.time) {
            onsets.append(event)
        }
        coveredUntil[source] = max(coveredUntil[source] ?? -Double.infinity, time)
        lastReceived[source] = now
        // 古いオンセットは捨てる(3秒より前のものは、もう使わない)
        onsets.removeAll { $0.time < time - 3 }
        muteIntervals.removeAll { $0.end < time - 3 }
    }

    /// フィードバック(クリック音・触覚)を出したので、しばらく音・振動を無視する
    func muteFeedback(at time: Double) {
        muteIntervals.append((time, time + config.feedbackMute))
        onsets.removeAll { isMuted($0.time) }
    }

    private func isMuted(_ time: Double) -> Bool {
        muteIntervals.contains { time >= $0.start && time <= $0.end }
    }

    /// そのセンサーが今動いているか(使う設定で、最近データが届いている)
    private func isActive(_ source: OnsetEvent.Source, now: Double) -> Bool {
        let enabled = source == .audio ? useAudio : useMotion
        guard enabled, let last = lastReceived[source] else { return false }
        return now - last <= config.staleAfter
    }

    /// 保留中の候補のうち、判断できるものを判断して返す
    func resolve(now: Double) -> [Decision] {
        var decisions: [Decision] = []
        var stillPending: [(time: Double, payload: Payload)] = []
        let activeSources = [OnsetEvent.Source.audio, .motion].filter { isActive($0, now: now) }

        for candidate in pending {
            let t = candidate.time
            // 音も振動も使わない設定 → カメラだけで確定
            if !useAudio && !useMotion {
                decisions.append(Decision(payload: candidate.payload, time: t, audio: nil, motion: nil,
                                          accepted: true, note: nil))
                continue
            }
            // 使う設定だが、センサーが動いていない → 入力が止まらないようにカメラだけで確定
            if activeSources.isEmpty {
                decisions.append(Decision(payload: candidate.payload, time: t, audio: nil, motion: nil,
                                          accepted: true, note: "音・振動のデータなし(カメラのみ)"))
                continue
            }

            let audio = activeSources.contains(.audio) ? closestOnset(.audio, to: t) : nil
            let motion = activeSources.contains(.motion) ? closestOnset(.motion, to: t) : nil
            if audio != nil || motion != nil {
                decisions.append(Decision(payload: candidate.payload, time: t, audio: audio, motion: motion,
                                          accepted: true, note: nil))
                continue
            }

            // 窓の終わりまでデータが届いたのに、何も無い → 却下
            let windowEnd = t + config.windowAfter
            let allCovered = activeSources.allSatisfy { (coveredUntil[$0] ?? -Double.infinity) >= windowEnd }
            if allCovered {
                let names = activeSources.map { $0 == .audio ? "音" : "振動" }.joined(separator: "・")
                decisions.append(Decision(payload: candidate.payload, time: t, audio: nil, motion: nil,
                                          accepted: false, note: "\(names)なし"))
            } else if now - t > config.maxWait {
                // データが遅れすぎている → 待つのをやめてカメラだけで確定
                decisions.append(Decision(payload: candidate.payload, time: t, audio: nil, motion: nil,
                                          accepted: true, note: "音の到着が遅いためカメラのみ"))
            } else {
                stillPending.append(candidate)
            }
        }
        pending = stillPending
        return decisions
    }

    /// 窓の中で、時刻がいちばん近いオンセット
    private func closestOnset(_ source: OnsetEvent.Source, to time: Double) -> OnsetEvent? {
        onsets
            .filter { $0.source == source && $0.time >= time - config.windowBefore && $0.time <= time + config.windowAfter }
            .min { abs($0.time - time) < abs($1.time - time) }
    }
}
