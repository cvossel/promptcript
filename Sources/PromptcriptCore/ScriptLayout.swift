import Foundation

/// Eine Bildschirmzeile im Prompter.
public struct DisplayLine: Hashable, Sendable {
    public let kind: BlockKind
    public let tokens: [ScriptToken]

    /// Bereich der gesprochenen Wörter in dieser Zeile, `nil` wenn die Zeile nichts Gesprochenes enthält.
    public var spokenRange: Range<Int>? {
        let ranges = tokens.map(\.spokenRange).filter { !$0.isEmpty }
        guard let first = ranges.first, let last = ranges.last else { return nil }
        return first.lowerBound..<last.upperBound
    }
}

/// Bricht das Skript für eine gegebene Breite in Zeilen um und beantwortet,
/// in welcher Zeile ein gesprochenes Wort steht.
public struct ScriptLayout: Sendable {
    public let lines: [DisplayLine]
    /// Für jedes gesprochene Wort der Index der Zeile, in der es steht.
    private let lineForSpoken: [Int]

    /// - Parameters:
    ///   - measure: Breite eines Tokens in Punkten (abhängig von Stil und Blockart).
    ///   - spaceWidth: Breite eines Leerzeichens für die Blockart.
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

    /// Zeile, in der das als Nächstes zu lesende Wort steht.
    /// Ist das Skript zu Ende gelesen, bleibt die letzte Zeile stehen.
    public func lineIndex(forCursor cursor: Int) -> Int {
        guard !lineForSpoken.isEmpty else { return 0 }
        let clamped = min(max(cursor, 0), lineForSpoken.count - 1)
        return lineForSpoken[clamped]
    }

    /// Cursor (erstes gesprochenes Wort) der Zeile `lineIndex(forCursor:) + delta`.
    /// Zeilen ohne gesprochene Wörter (Überschriften) werden übersprungen.
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
