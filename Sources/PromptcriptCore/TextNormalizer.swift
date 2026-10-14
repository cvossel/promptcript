import Foundation

/// Brings script text and recognized text into a common, comparable form:
/// lowercase, without accents/umlauts, without punctuation, number words as digits.
/// German and English number words are supported.
public enum TextNormalizer {
    static let numberWords: [String: String] = [
        "null": "0", "zero": "0",
        "eins": "1", "one": "1",
        "zwei": "2", "two": "2",
        "drei": "3", "three": "3",
        "vier": "4", "four": "4",
        "funf": "5", "five": "5",
        "sechs": "6", "six": "6",
        "sieben": "7", "seven": "7",
        "acht": "8", "eight": "8",
        "neun": "9", "nine": "9",
        "zehn": "10", "ten": "10",
        "elf": "11", "eleven": "11",
        "zwolf": "12", "twelve": "12",
    ]

    /// Splits text into normalized words. Hyphens, apostrophes etc. separate words,
    /// so that e.g. "Teleprompter-App" and "Teleprompter App" are treated the same.
    public static func words(in text: String) -> [String] {
        let folded = text
            .replacingOccurrences(of: "ß", with: "ss")
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .lowercased()
        var result: [String] = []
        var current = String.UnicodeScalarView()
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                current.append(scalar)
            } else if !current.isEmpty {
                result.append(canonical(String(current)))
                current = String.UnicodeScalarView()
            }
        }
        if !current.isEmpty {
            result.append(canonical(String(current)))
        }
        return result
    }

    static func canonical(_ word: String) -> String {
        numberWords[word] ?? word
    }
}

/// Similarity of two normalized words, between 0 and 1.
public enum WordSimilarity {
    /// - Parameter allowPrefix: Rate inflections/compounds generously via a shared word start.
    ///   Must be off when comparing joined words, otherwise "hallo" would match "hallo"+"und".
    public static func score(_ a: String, _ b: String, allowPrefix: Bool = true) -> Double {
        if a == b { return 1 }
        let la = a.count
        let lb = b.count
        let shorter = min(la, lb)
        // Short words ("und", "die", "it") must match exactly, otherwise there are too many accidental matches.
        if shorter <= 3 { return 0 }
        let distance = levenshtein(Array(a), Array(b))
        var similarity = 1 - Double(distance) / Double(max(la, lb))
        // Inflections and compounds ("Prompter" ↔ "Promptern", "Teleprompter" ↔ "Teleprompterapp").
        if allowPrefix, shorter >= 5, a.hasPrefix(b) || b.hasPrefix(a) {
            similarity = max(similarity, 0.78)
        }
        return similarity
    }

    static func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = Array(repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}
