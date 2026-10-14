import Foundation

/// Findet anhand der zuletzt gesprochenen Wörter die aktuelle Stelle im Skript.
///
/// Verfahren: lokale Sequenz-Alignierung (Smith-Waterman) der letzten erkannten Wörter
/// gegen ein Fenster des Skripts rund um die aktuelle Position. Dadurch toleriert der
/// Abgleich falsch erkannte Wörter, ausgelassene Wörter, eingeschobene Füllwörter und
/// zusammen- bzw. getrennt geschriebene Begriffe. Sprünge nach vorne sind leicht,
/// Sprünge zurück und große Sprünge brauchen deutlich mehr Übereinstimmung.
public final class ScriptMatcher {
    public struct Configuration: Sendable {
        /// Wie viele Wörter vor der aktuellen Position noch gesucht werden.
        public var backWindow = 12
        /// Wie viele Wörter nach der aktuellen Position gesucht werden.
        public var forwardWindow = 45
        /// Wie viele der zuletzt gesprochenen Wörter verglichen werden.
        public var recentCount = 8
        /// Ab dieser Ähnlichkeit gelten zwei Wörter als Treffer.
        public var matchThreshold = 0.72
        /// Strengere Schwelle für zusammengefügte Wörter.
        public var mergedThreshold = 0.85
        public var mismatchPenalty = -0.7
        /// Gesprochenes Wort ohne Gegenstück im Skript (Füllwort, Versprecher, Improvisation).
        public var extraSpokenPenalty = -0.6
        /// Skriptwort, das nicht gesprochen bzw. nicht erkannt wurde.
        public var skippedScriptPenalty = -0.45
        /// Mindestpunktzahl für einen normalen Schritt nach vorne (≈ zwei passende Wörter).
        public var minScore = 1.6
        /// Ab so vielen Wörtern gilt ein Sprung nach vorne als „groß“.
        public var farJump = 15
        public var farJumpScore = 2.6
        /// Mindestpunktzahl, um zurückzuspringen (z. B. wenn ein Satz neu begonnen wird).
        public var backJumpScore = 3.0
        /// Kleinere Rücksprünge werden ignoriert: Sie entstehen meist nur dadurch, dass die
        /// Erkennung ein vorläufiges Ergebnis korrigiert, und würden die Anzeige flackern lassen.
        public var minBackJump = 3
        /// Bevorzugt bei gleich guten Treffern die Stelle nahe der aktuellen Position.
        public var distancePenalty = 0.03

        public init() {}
    }

    public let words: [String]
    public let configuration: Configuration
    /// Index des zuletzt gesprochenen Skriptworts, -1 vor dem ersten Wort.
    public private(set) var position: Int = -1

    /// Index des als Nächstes zu lesenden Worts.
    public var cursor: Int { position + 1 }

    public init(words: [String], configuration: Configuration = Configuration()) {
        self.words = words
        self.configuration = configuration
    }

    /// Setzt die Position manuell, z. B. nach Pfeiltasten.
    public func reset(toCursor cursor: Int) {
        position = min(max(cursor, 0), words.count) - 1
    }

    /// Gleicht die zuletzt gesprochenen (normalisierten) Wörter ab.
    /// - Returns: `true`, wenn sich die Position geändert hat.
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
                // Zwei Skriptwörter als ein erkanntes Wort („Teleprompter App“ → „teleprompterapp“).
                if j >= 2 {
                    let merged = WordSimilarity.score(spoken[i - 1], window[j - 2] + window[j - 1], allowPrefix: false)
                    if merged >= config.mergedThreshold {
                        best = max(best, h[i - 1][j - 2] + 1.5 * merged)
                    }
                }
                // Ein Skriptwort als zwei erkannte Wörter („Livestream“ → „live stream“).
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

        // Ein einzelnes, eindeutiges Wort genügt, wenn es unmittelbar folgt (z. B. ganz am Anfang).
        let isNextWord = bestPosition > position && bestPosition - position <= 2
        let singleWordOK = isNextWord && bestScore >= 0.9 && words[bestPosition].count >= 4

        guard bestScore >= required || singleWordOK else { return false }
        position = bestPosition
        return true
    }
}
