import Foundation

/// 練習モード: お題の文を表示し、入力の正解率と速さを測る。
///
/// - 正解率 = 正しく打った回数 ÷ 打った回数(バックスペースで消しても、打ち間違えた記録は残る)
/// - 速さ = 1分あたりの文字数(CPM)。英語の慣習では 5 文字 = 1 単語として WPM = CPM ÷ 5
struct PracticeSession: Equatable {
    /// お題(このキーボードで打てる文字だけ: a〜z、; , . とスペース)
    static let sentences: [String] = [
        "asdf jkl;",
        "fjfj dkdk sls; a;a;",
        "the quick brown fox",
        "jumps over the lazy dog.",
        "hello, world.",
        "type on your knees",
        "practice makes perfect.",
        "a sad lad asks dad",
    ]

    /// 文字ごとの状態(画面の色分けに使う)
    enum CharacterState: Equatable {
        case correct   // 正しく打てた
        case wrong     // 打ち間違えた
        case current   // 次に打つ文字
        case pending   // まだ
    }

    private(set) var sentenceIndex: Int
    private(set) var typed: String = ""
    private(set) var correctCount = 0
    private(set) var totalCount = 0
    private(set) var startTime: Double?
    private(set) var endTime: Double?

    init(sentenceIndex: Int = 0) {
        self.sentenceIndex = sentenceIndex % Self.sentences.count
    }

    var target: String { Self.sentences[sentenceIndex] }

    var isFinished: Bool { typed.count >= target.count }

    /// 正解率(0〜1)。まだ何も打っていなければ 1。
    var accuracy: Double {
        totalCount == 0 ? 1 : Double(correctCount) / Double(totalCount)
    }

    /// 1分あたりの文字数(打った文字数 ÷ 経過時間)
    func charactersPerMinute(now: Double) -> Double {
        guard let startTime else { return 0 }
        let elapsed = (endTime ?? now) - startTime
        guard elapsed > 0.5 else { return 0 }  // 打ち始め直後は値が暴れるので出さない
        return Double(typed.count) / elapsed * 60
    }

    /// 文字を入力する(改行は練習では使わないので無視)
    mutating func input(_ text: String, at time: Double) {
        for character in text where character != "\n" {
            guard !isFinished else { return }
            if startTime == nil { startTime = time }
            let expected = Array(target)[typed.count]
            totalCount += 1
            if character == expected { correctCount += 1 }
            typed.append(character)
            if isFinished { endTime = time }
        }
    }

    mutating func backspace() {
        guard !typed.isEmpty, !isFinished else { return }
        typed.removeLast()
    }

    /// 次のお題へ(成績はリセット)
    mutating func next() {
        self = PracticeSession(sentenceIndex: sentenceIndex + 1)
    }

    /// お題の文字ごとの状態
    var characterStates: [(character: Character, state: CharacterState)] {
        let typedCharacters = Array(typed)
        return Array(target).enumerated().map { index, character in
            if index < typedCharacters.count {
                return (character, typedCharacters[index] == character ? .correct : .wrong)
            }
            return (character, index == typedCharacters.count ? .current : .pending)
        }
    }

    static func == (lhs: PracticeSession, rhs: PracticeSession) -> Bool {
        lhs.sentenceIndex == rhs.sentenceIndex && lhs.typed == rhs.typed
            && lhs.correctCount == rhs.correctCount && lhs.totalCount == rhs.totalCount
            && lhs.startTime == rhs.startTime && lhs.endTime == rhs.endTime
    }
}
