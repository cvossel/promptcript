import Foundation

public struct TokenStyle: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let bold = TokenStyle(rawValue: 1 << 0)
    public static let italic = TokenStyle(rawValue: 1 << 1)
    public static let code = TokenStyle(rawValue: 1 << 2)
}

public enum BlockKind: Hashable, Sendable {
    case paragraph
    case heading(level: Int)
    case listItem

    public var isHeading: Bool {
        if case .heading = self { return true }
        return false
    }
}

/// Ein angezeigtes Wort (inkl. Satzzeichen) mit Formatierung.
/// `spokenRange` verweist auf die normalisierten Wörter in `Script.spokenWords`;
/// leer bei Überschriften, Aufzählungszeichen und reinen Satzzeichen.
public struct ScriptToken: Hashable, Sendable {
    public let text: String
    public let style: TokenStyle
    public let spokenRange: Range<Int>

    public init(text: String, style: TokenStyle, spokenRange: Range<Int>) {
        self.text = text
        self.style = style
        self.spokenRange = spokenRange
    }
}

public struct ScriptBlock: Hashable, Sendable {
    public let kind: BlockKind
    public let tokens: [ScriptToken]
}

/// Das geparste Skript: Blöcke zur Anzeige und die Liste der zu sprechenden Wörter.
public struct Script: Sendable {
    public let blocks: [ScriptBlock]
    public let spokenWords: [String]

    public static let empty = Script(blocks: [], spokenWords: [])

    /// Parst Markdown. Jede Zeile im Quelltext wird zu einem eigenen Absatz,
    /// weil eingefügte Texte ihre Zeilenumbrüche meist bewusst setzen.
    /// Überschriften werden angezeigt, aber nicht als gesprochener Text erwartet.
    public static func parse(_ markdown: String) -> Script {
        var blocks: [ScriptBlock] = []
        var spoken: [String] = []
        var inCodeFence = false

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                inCodeFence.toggle()
                continue
            }
            if line.isEmpty || isHorizontalRule(line) || isComment(line) { continue }

            var kind = BlockKind.paragraph
            var content = line
            var prefix: String?

            if !inCodeFence {
                if let (level, rest) = heading(line) {
                    kind = .heading(level: level)
                    content = rest
                } else if let (marker, rest) = listItem(line) {
                    kind = .listItem
                    prefix = marker
                    content = rest
                } else if line.hasPrefix(">") {
                    content = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
                }
            }

            var tokens: [ScriptToken] = []
            if let prefix {
                tokens.append(ScriptToken(text: prefix, style: [], spokenRange: spoken.count..<spoken.count))
            }
            tokens += inlineTokens(content, isSpoken: !kind.isHeading, plain: inCodeFence, spoken: &spoken)
            if !tokens.isEmpty {
                blocks.append(ScriptBlock(kind: kind, tokens: tokens))
            }
        }
        return Script(blocks: blocks, spokenWords: spoken)
    }

    /// Wörter aus dem Skript, die der Spracherkennung als Vokabelhinweis mitgegeben werden.
    /// Bevorzugt werden Fachbegriffe: Abkürzungen, CamelCase, Ziffern, englisch wirkende und lange Wörter.
    public func contextualVocabulary(limit: Int = 100) -> [String] {
        var seen = Set<String>()
        var candidates: [(word: String, score: Int, order: Int)] = []
        let englishHints = ["th", "ee", "oo", "ea", "sh", "ou", "ay", "ow", "ight", "y", "w", "c"]

        for block in blocks {
            for token in block.tokens {
                for part in token.text.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "-" }) {
                    let word = part.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
                    guard word.count >= 3, seen.insert(word.lowercased()).inserted else { continue }
                    var score = min(word.count, 12)
                    let letters = Array(word)
                    if letters.dropFirst().contains(where: \.isUppercase) { score += 8 }
                    if letters.contains(where: \.isNumber) { score += 6 }
                    let lower = word.lowercased()
                    if englishHints.contains(where: { lower.contains($0) }) && !lower.contains("sch") && !lower.contains("ch") {
                        score += 5
                    }
                    candidates.append((word, score, candidates.count))
                }
            }
        }
        return candidates
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.order < $1.order }
            .prefix(limit)
            .map(\.word)
    }

    // MARK: - Parsing-Helfer

    private static func heading(_ line: String) -> (Int, String)? {
        let hashes = line.prefix(while: { $0 == "#" })
        guard (1...6).contains(hashes.count) else { return nil }
        let rest = line.dropFirst(hashes.count)
        guard rest.first == " " else { return nil }
        return (hashes.count, rest.trimmingCharacters(in: .whitespaces))
    }

    private static func listItem(_ line: String) -> (String, String)? {
        if let first = line.first, "-*+".contains(first), line.dropFirst().first == " " {
            return ("•", String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces))
        }
        let digits = line.prefix(while: \.isNumber)
        if !digits.isEmpty, digits.count <= 3 {
            let rest = line.dropFirst(digits.count)
            if let marker = rest.first, ".)".contains(marker), rest.dropFirst().first == " " {
                return (digits + ".", String(rest.dropFirst(2)).trimmingCharacters(in: .whitespaces))
            }
        }
        return nil
    }

    private static func isHorizontalRule(_ line: String) -> Bool {
        let compact = line.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3, let first = compact.first, "-*_".contains(first) else { return false }
        return compact.allSatisfy { $0 == first }
    }

    private static func isComment(_ line: String) -> Bool {
        line.hasPrefix("<!--") && line.hasSuffix("-->")
    }

    private static func inlineTokens(_ content: String, isSpoken: Bool, plain: Bool, spoken: inout [String]) -> [ScriptToken] {
        let attributed: AttributedString
        if plain {
            attributed = AttributedString(content)
        } else {
            attributed = (try? AttributedString(
                markdown: content,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )) ?? AttributedString(content)
        }

        var tokens: [ScriptToken] = []
        var word = ""
        var wordStyle: TokenStyle = []

        func flush() {
            guard !word.isEmpty else { return }
            let start = spoken.count
            if isSpoken {
                spoken += TextNormalizer.words(in: word)
            }
            tokens.append(ScriptToken(text: word, style: wordStyle, spokenRange: start..<spoken.count))
            word = ""
        }

        for run in attributed.runs {
            var style: TokenStyle = plain ? [.code] : []
            if let intent = run.inlinePresentationIntent {
                if intent.contains(.stronglyEmphasized) { style.insert(.bold) }
                if intent.contains(.emphasized) { style.insert(.italic) }
                if intent.contains(.code) { style.insert(.code) }
            }
            for character in attributed[run.range].characters {
                if character.isWhitespace {
                    flush()
                } else {
                    if word.isEmpty { wordStyle = style }
                    word.append(character)
                }
            }
        }
        flush()
        return tokens
    }
}
