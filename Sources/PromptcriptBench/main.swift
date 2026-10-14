import AVFoundation
import Foundation
import PromptcriptCore
import Speech

// Entwicklerwerkzeug: Spielt eine Audiodatei durch SpeechAnalyzer und zeigt,
// wie der Abgleich dem Skript folgt. So lässt sich die Fehlertoleranz ohne Mikrofon testen.
//
//   swift run PromptcriptBench <skript.md> <audio.aiff> [de-DE|en-US]

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    print("Aufruf: PromptcriptBench <skript.md> <audio> [de-DE|en-US]")
    exit(1)
}

let script = Script.parse(try String(contentsOfFile: arguments[1], encoding: .utf8))
let audioURL = URL(fileURLWithPath: arguments[2])
let locale = Locale(identifier: arguments.count > 3 ? arguments[3] : "de-DE")

let matcher = ScriptMatcher(words: script.spokenWords)
var buffer = TranscriptBuffer()

func context(at cursor: Int) -> String {
    let words = script.spokenWords
    let before = words[max(0, cursor - 4)..<min(cursor, words.count)].joined(separator: " ")
    let after = words[min(cursor, words.count)..<min(words.count, cursor + 4)].joined(separator: " ")
    return "… \(before) ▸ \(after) …"
}

guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
    print("Sprache nicht unterstützt")
    exit(1)
}
let transcriber = SpeechTranscriber(
    locale: supported,
    transcriptionOptions: [],
    reportingOptions: [.volatileResults, .fastResults],
    attributeOptions: []
)
if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
    print("Lade Sprachmodell …")
    try await request.downloadAndInstall()
}

let analyzer = SpeechAnalyzer(modules: [transcriber])
let vocabulary = script.contextualVocabulary(limit: 100)
if !vocabulary.isEmpty {
    let analysisContext = AnalysisContext()
    analysisContext.contextualStrings[.general] = vocabulary
    do {
        try await analyzer.setContext(analysisContext)
    } catch {
        print("Hinweis: Vokabelhinweise nicht unterstützt (\(error.localizedDescription))")
    }
}

let resultsTask = Task {
    for try await result in transcriber.results {
        let text = String(result.text.characters)
        if result.isFinal {
            buffer.applyFinal(text)
        } else {
            buffer.applyVolatile(text)
        }
        let moved = matcher.update(recentWords: buffer.recentWords)
        let marker = result.isFinal ? "FINAL" : "     "
        print("\(marker) \(moved ? "→" : " ") \(String(format: "%3d", matcher.cursor))/\(script.spokenWords.count)  \(context(at: matcher.cursor))   [\(text.suffix(50))]")
    }
}

let file = try AVAudioFile(forReading: audioURL)
try await analyzer.start(inputAudioFile: file, finishAfterFile: true)
try await resultsTask.value

print("\nErgebnis: \(matcher.cursor) von \(script.spokenWords.count) Wörtern erreicht.")
