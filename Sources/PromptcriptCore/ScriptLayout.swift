import Foundation

/// One on-screen line in the prompter.
public struct DisplayLine: Hashable, Sendable {
    public let kind: BlockKind
    public let tokens: [ScriptToken]

    /// Range of spoken words in this line, `nil` if the line contains nothing spoken.
    public var spokenRange: Range<Int>? {
        let ranges = tokens.map(\.spokenRange).filter { !$0.isEmpty }
        guard let first = ranges.first, let last = ranges.last else { return nil }
        return first.lowerBound..<last.upperBound
    }
}

/// Wraps the script into lines for a given width and answers
/// which line a spoken word is on.
public struct ScriptLayout: Sendable {
    public let lines: [DisplayLine]
    /// For each spoken word, the index of the line it is on.
    private let lineForSpoken: [Int]

    /// - Parameters:
    ///   - measure: Width of a token in points (depends on style and block kind).
    ///   - spaceWidth: Width of a space for the block kind.
    public init(
        script: Script,
        maxWidth: Double,
        measure: (ScriptToken, BlockKind) -> Double,
        spaceWidth: (BlockKind) -> Double
    ) {
        var lines: [DisplayLine] = []
        for block in script.blocks {
            let space = spaceWidth(block.kind)
            var current: [ScriptToken] = []
            var width = 0.0
            for token in block.tokens {
                let tokenWidth = measure(token, block.kind)
                let needed = current.isEmpty ? tokenWidth : width + space + tokenWidth
                if needed > maxWidth, !current.isEmpty {
                    lines.append(DisplayLine(kind: block.kind, tokens: current))
                    current = [token]
                    width = tokenWidth
                } else {
                    current.append(token)
                    width = needed
                }
            }
            if !current.isEmpty {
                lines.append(DisplayLine(kind: block.kind, tokens: current))
            }
        }

        var mapping = Array(repeating: 0, count: script.spokenWords.count)
        for (index, line) in lines.enumerated() {
            for token in line.tokens {
                for spokenIndex in token.spokenRange {
                    mapping[spokenIndex] = index
                }
            }
        }
        self.lines = lines
        self.lineForSpoken = mapping
    }

    /// The line containing the next word to be read.
    /// Once the script has been read to the end, the last line stays in place.
    public func lineIndex(forCursor cursor: Int) -> Int {
        guard !lineForSpoken.isEmpty else { return 0 }
        let clamped = min(max(cursor, 0), lineForSpoken.count - 1)
        return lineForSpoken[clamped]
    }

    /// Cursor (first spoken word) of the line `lineIndex(forCursor:) + delta`.
    /// Lines without spoken words (headings) are skipped.
    public func cursor(movingLinesFrom cursor: Int, by delta: Int) -> Int? {
        guard !lines.isEmpty, delta != 0 else { return nil }
        var index = lineIndex(forCursor: cursor)
        var remaining = abs(delta)
        let step = delta > 0 ? 1 : -1
        var result: Int?
        while remaining > 0 {
            index += step
            guard lines.indices.contains(index) else { break }
            if let range = lines[index].spokenRange {
                result = range.lowerBound
                remaining -= 1
            }
        }
        return result
    }
}
