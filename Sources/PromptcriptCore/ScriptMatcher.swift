import Foundation

/// Finds the current position in the script based on the most recently spoken words.
///
/// Method: local sequence alignment (Smith-Waterman) of the last recognized words
/// against a window of the script around the current position. This lets the matcher
/// tolerate misrecognized words, skipped words, inserted filler words and terms that
/// are recognized as joined or split. Jumping forward is easy; jumping back and
/// large jumps require considerably more agreement.
public final class ScriptMatcher {
    public struct Configuration: Sendable {
        /// How many words before the current position are still searched.
        public var backWindow = 12
        /// How many words after the current position are searched.
        public var forwardWindow = 45
        /// How many of the most recently spoken words are compared.
        public var recentCount = 8
        /// Two words count as a match from this similarity upward.
        public var matchThreshold = 0.72
        /// Stricter threshold for joined words.
        public var mergedThreshold = 0.85
        public var mismatchPenalty = -0.7
        /// Spoken word with no counterpart in the script (filler, slip of the tongue, ad-lib).
        public var extraSpokenPenalty = -0.6
        /// Script word that was not spoken or not recognized.
        public var skippedScriptPenalty = -0.45
        /// Minimum score for a normal step forward (≈ two matching words).
        public var minScore = 1.6
        /// A forward jump of at least this many words counts as "far".
        public var farJump = 15
        public var farJumpScore = 2.6
        /// Minimum score to jump back (e.g. when a sentence is restarted).
        public var backJumpScore = 3.0
        /// Smaller backward jumps are ignored: they usually only happen because the recognizer
        /// corrects a volatile result, and they would make the display flicker.
        public var minBackJump = 3
        /// Among equally good matches, prefers the one closest to the current position.
        public var distancePenalty = 0.03

        public init() {}
    }

    public let words: [String]
    public let configuration: Configuration
    /// Index of the last spoken script word, -1 before the first word.
    public private(set) var position: Int = -1

    /// Index of the next word to be read.
    public var cursor: Int { position + 1 }

    public init(words: [String], configuration: Configuration = Configuration()) {
        self.words = words
        self.configuration = configuration
    }

    /// Sets the position manually, e.g. after arrow keys.
    public func reset(toCursor cursor: Int) {
        position = min(max(cursor, 0), words.count) - 1
    }

    /// Matches the most recently spoken (normalized) words.
    /// - Returns: `true` if the position changed.
    @discardableResult
    public func update(recentWords: [String]) -> Bool {
        let config = configuration
        let spoken = Array(recentWords.suffix(config.recentCount))
        guard !spoken.isEmpty, !words.isEmpty else { return false }

        let lower = max(0, position - config.backWindow)
        let upper = min(words.count, position + 1 + config.forwardWindow)
        guard lower < upper else { return false }
        let window = Array(words[lower..<upper])

        let m = spoken.count
        let n = window.count
        var h = Array(repeating: Array(repeating: 0.0, count: n + 1), count: m + 1)

        for i in 1...m {
            for j in 1...n {
                var best = 0.0
                let similarity = WordSimilarity.score(spoken[i - 1], window[j - 1])
                let diagonal = similarity >= config.matchThreshold ? similarity : config.mismatchPenalty
                best = max(best, h[i - 1][j - 1] + diagonal)
                best = max(best, h[i - 1][j] + config.extraSpokenPenalty)
                best = max(best, h[i][j - 1] + config.skippedScriptPenalty)
                // Two script words recognized as one word ("Teleprompter App" → "teleprompterapp").
                if j >= 2 {
                    let merged = WordSimilarity.score(spoken[i - 1], window[j - 2] + window[j - 1], allowPrefix: false)
                    if merged >= config.mergedThreshold {
                        best = max(best, h[i - 1][j - 2] + 1.5 * merged)
                    }
                }
                // One script word recognized as two words ("Livestream" → "live stream").
                if i >= 2 {
                    let merged = WordSimilarity.score(spoken[i - 2] + spoken[i - 1], window[j - 1], allowPrefix: false)
                    if merged >= config.mergedThreshold {
                        best = max(best, h[i - 2][j - 1] + 1.5 * merged)
                    }
                }
                h[i][j] = best
            }
        }

        var bestPosition = -1
        var bestScore = 0.0
        var bestAdjusted = -Double.infinity
        for j in 1...n {
            let score = h[m][j]
            guard score > 0 else { continue }
            let candidate = lower + j - 1
            let adjusted = score - config.distancePenalty * Double(abs(candidate - position))
            if adjusted > bestAdjusted {
                bestAdjusted = adjusted
                bestScore = score
                bestPosition = candidate
            }
        }

        guard bestPosition >= 0, bestPosition != position else { return false }

        let required: Double
        if bestPosition < position {
            guard position - bestPosition >= config.minBackJump else { return false }
            required = config.backJumpScore
        } else if bestPosition - position > config.farJump {
            required = config.farJumpScore
        } else {
            required = config.minScore
        }

        // A single, unambiguous word is enough if it follows immediately (e.g. at the very start).
        let isNextWord = bestPosition > position && bestPosition - position <= 2
        let singleWordOK = isNextWord && bestScore >= 0.9 && words[bestPosition].count >= 4

        guard bestScore >= required || singleWordOK else { return false }
        position = bestPosition
        return true
    }
}
