import Foundation

/// Bringt Skript-Text und erkannten Text in eine gemeinsame, vergleichbare Form:
/// Kleinschreibung, ohne Akzente/Umlaute, ohne Satzzeichen, Zahlwörter als Ziffern.
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

    /// Zerlegt Text in normalisierte Wörter. Bindestriche, Apostrophe usw. trennen Wörter,
    /// damit z. B. „Teleprompter-App“ und „Teleprompter App“ gleich behandelt werden.
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

/// Ähnlichkeit zweier normalisierter Wörter zwischen 0 und 1.
public enum WordSimilarity {
    /// - Parameter allowPrefix: Beugungen/Komposita über gemeinsamen Wortanfang großzügig werten.
    ///   Beim Vergleich zusammengefügter Wörter muss das aus sein, sonst passt „hallo“ auf „hallo“+„und“.
    public static func score(_ a: String, _ b: String, allowPrefix: Bool = true) -> Double {
        if a == b { return 1 }
        let la = a.count
        let lb = b.count
        let shorter = min(la, lb)
        // Kurze Wörter („und“, „die“, „it“) müssen exakt passen, sonst gibt es zu viele Zufallstreffer.
        if shorter <= 3 { return 0 }
        let distance = levenshtein(Array(a), Array(b))
        var similarity = 1 - Double(distance) / Double(max(la, lb))
        // Beugungen und Komposita („Prompter“ ↔ „Promptern“, „Teleprompter“ ↔ „Teleprompterapp“).
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
