import Testing
@testable import PromptcriptCore

/// Simulates a speech recognizer that delivers volatile results word by word
/// and a final result after each phrase.
private struct Session {
    let matcher: ScriptMatcher
    var buffer = TranscriptBuffer()
    var segment: [String] = []

    init(_ script: String) {
        matcher = ScriptMatcher(words: Script.parse(script).spokenWords)
    }

    /// Speaks words one at a time (volatile) and finalizes the segment at the end.
    mutating func say(_ text: String) {
        for word in text.split(separator: " ") {
            segment.append(String(word))
            buffer.applyVolatile(segment.joined(separator: " "))
            matcher.update(recentWords: buffer.recentWords)
        }
        buffer.applyFinal(segment.joined(separator: " "))
        segment = []
        matcher.update(recentWords: buffer.recentWords)
    }

    var cursor: Int { matcher.cursor }
    var words: [String] { matcher.words }
}

// The test scripts are intentionally German: they exercise German speech input
// (umlauts, ß, German number words and filler words).
private let text = """
# Einleitung
Hallo und willkommen zu meinem neuen Video über Teleprompter.
Heute zeige ich euch, wie man mit Spracherkennung automatisch scrollt.
Wir nutzen dafür das Framework SpeechAnalyzer von Apple und ein bisschen Swift.
Am Ende gibt es noch einen kurzen Ausblick auf das Deployment.
"""

@Suite struct ScriptMatcherTests {
    @Test func followsExactReading() {
        var session = Session(text)
        session.say("Hallo und willkommen zu meinem neuen Video")
        #expect(session.words[session.cursor] == "uber")
        session.say("über Teleprompter Heute zeige ich euch")
        #expect(session.words[session.cursor] == "wie")
    }

    @Test func startsOnFirstWord() {
        var session = Session(text)
        session.say("Hallo")
        #expect(session.cursor == 1)
    }

    @Test func toleratesMisrecognizedWords() {
        var session = Session(text)
        session.say("Hallo und willkommen zu meinem neuen Video über Teleprompter")
        // "SpeechAnalyzer" and "Framework" are misrecognized.
        session.say("Heute zeige ich euch wie man mit Sprach Erkennung automatisch scrollt")
        session.say("wir nutzen dafür das Frame Work Spiegel Analyse von Apple und ein bisschen Swift")
        #expect(session.words[session.cursor] == "am")
    }

    @Test func toleratesFillersAndAdLibs() {
        var session = Session(text)
        session.say("Hallo äh und willkommen ähm zu meinem neuen also Video über Teleprompter")
        #expect(session.words[session.cursor] == "heute")
    }

    @Test func toleratesSkippedWords() {
        var session = Session(text)
        session.say("Hallo willkommen zu meinem Video über Teleprompter")
        #expect(session.words[session.cursor] == "heute")
    }

    @Test func staysPutDuringUnrelatedTalk() {
        var session = Session(text)
        session.say("Hallo und willkommen zu meinem neuen Video")
        let before = session.cursor
        session.say("oh warte mal kurz da war gerade etwas mit dem Licht")
        #expect(session.cursor == before)
    }

    @Test func doesNotJumpBackOnSingleCommonWord() {
        var session = Session(text)
        session.say("Hallo und willkommen zu meinem neuen Video über Teleprompter Heute zeige ich euch")
        let before = session.cursor
        session.say("und")
        #expect(session.cursor >= before)
    }

    @Test func jumpsBackWhenSentenceIsRestarted() {
        var session = Session(text)
        session.say("Heute zeige ich euch wie man mit Spracherkennung automatisch scrollt")
        let afterSentence = session.cursor
        session.say("Heute zeige ich euch wie man")
        #expect(session.cursor < afterSentence)
        #expect(session.words[session.cursor] == "mit")
    }

    @Test func handlesCompoundSplits() {
        var session = Session("Das ist ein Livestream über die Teleprompter-App für alle.")
        session.say("Das ist ein Live Stream über die Teleprompterapp für alle")
        #expect(session.cursor == session.words.count)
    }

    @Test func numbersMatchDigits() {
        var session = Session("Ich habe drei Tipps für euch heute.")
        session.say("Ich habe 3 Tipps für euch")
        #expect(session.words[session.cursor] == "heute")
    }
}

@Suite struct ScriptParsingTests {
    @Test func headingsAreNotSpoken() {
        let script = Script.parse("# Titel\nHallo Welt")
        #expect(script.spokenWords == ["hallo", "welt"])
        #expect(script.blocks.count == 2)
        #expect(script.blocks[0].kind == .heading(level: 1))
    }

    @Test func inlineFormattingIsKept() {
        let script = Script.parse("Das ist **wirklich** *wichtig*, oder `code`?")
        let styles = script.blocks[0].tokens.map(\.style)
        #expect(styles[2] == .bold)
        #expect(styles[3] == .italic)
        #expect(styles[5] == .code)
        #expect(script.blocks[0].tokens[3].text == "wichtig,")
        #expect(script.spokenWords == ["das", "ist", "wirklich", "wichtig", "oder", "code"])
    }

    @Test func listItemsGetMarkers() {
        let script = Script.parse("- Erster Punkt\n2. Zweiter Punkt")
        #expect(script.blocks[0].tokens[0].text == "•")
        #expect(script.blocks[1].tokens[0].text == "2.")
        #expect(script.spokenWords == ["erster", "punkt", "zweiter", "punkt"])
    }

    @Test func normalizerFoldsUmlautsAndHyphens() {
        #expect(TextNormalizer.words(in: "Größe der Teleprompter-App!") == ["grosse", "der", "teleprompter", "app"])
    }

    @Test func vocabularyPrefersTechnicalTerms() {
        let script = Script.parse("Wir deployen mit GitHub Actions und SwiftUI auf den Server.")
        let vocab = script.contextualVocabulary(limit: 3)
        #expect(vocab.contains("GitHub"))
        #expect(vocab.contains("SwiftUI"))
    }
}

@Suite struct ScriptLayoutTests {
    private func layout(_ text: String, width: Double) -> ScriptLayout {
        ScriptLayout(
            script: Script.parse(text),
            maxWidth: width,
            measure: { token, _ in Double(token.text.count) },
            spaceWidth: { _ in 1 }
        )
    }

    @Test func wrapsAtWidth() {
        let layout = layout("aaa bbb ccc ddd", width: 7)
        #expect(layout.lines.count == 2)
        #expect(layout.lineIndex(forCursor: 0) == 0)
        #expect(layout.lineIndex(forCursor: 2) == 1)
        #expect(layout.lineIndex(forCursor: 99) == 1)
    }

    @Test func movingLinesSkipsHeadings() {
        let layout = layout("eins zwei\n# Kapitel\ndrei vier", width: 100)
        #expect(layout.lines.count == 3)
        #expect(layout.cursor(movingLinesFrom: 0, by: 1) == 2)
        #expect(layout.cursor(movingLinesFrom: 2, by: -1) == 0)
        #expect(layout.cursor(movingLinesFrom: 2, by: 1) == nil)
    }
}
