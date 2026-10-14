import Foundation

/// Collects speech recognition output: final results are appended,
/// volatile results keep replacing each other.
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

    /// The most recently spoken words, oldest first.
    public var recentWords: [String] {
        Array((finalized + volatile).suffix(capacity))
    }
}
