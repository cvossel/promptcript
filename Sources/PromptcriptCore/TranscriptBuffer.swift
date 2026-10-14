import Foundation

/// Sammelt die Ausgabe der Spracherkennung: endgültige Ergebnisse werden angehängt,
/// vorläufige („volatile“) Ergebnisse ersetzen sich laufend gegenseitig.
public struct TranscriptBuffer: Sendable {
    public private(set) var finalized: [String] = []
    public private(set) var volatile: [String] = []

    private let capacity = 40

    public init() {}

    public mutating func applyVolatile(_ text: String) {
        volatile = TextNormalizer.words(in: text)
    }

    public mutating func applyFinal(_ text: String) {
        finalized += TextNormalizer.words(in: text)
        if finalized.count > capacity {
            finalized.removeFirst(finalized.count - capacity)
        }
        volatile = []
    }

    public mutating func clear() {
        finalized = []
        volatile = []
    }

    /// Die zuletzt gesprochenen Wörter, älteste zuerst.
    public var recentWords: [String] {
        Array((finalized + volatile).suffix(capacity))
    }
}
