import AppKit
import Combine
import PromptcriptCore
import SwiftUI
import UniformTypeIdentifiers

enum PromptLanguage: String, CaseIterable, Identifiable {
    case german
    case english

    var id: String { rawValue }

    var title: String {
        switch self {
        case .german: "Deutsch"
        case .english: "English"
        }
    }

    var locale: Locale {
        switch self {
        case .german: Locale(identifier: "de-DE")
        case .english: Locale(identifier: "en-US")
        }
    }
}

enum PrompterStatus: Equatable {
    case idle
    case preparing(String)
    case listening
    case paused
    case error(String)
}

@MainActor
final class AppModel: ObservableObject {
    // MARK: Einstellungen (werden gespeichert)

    @Published var text: String {
        didSet { defaults.set(text, forKey: Keys.text) }
    }
    @Published var language: PromptLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: Keys.language)
            if isPrompting, oldValue != language { restartEngine() }
        }
    }
    @Published var engineKind: EngineKind {
        didSet {
            defaults.set(engineKind.rawValue, forKey: Keys.engine)
            if isPrompting, oldValue != engineKind { restartEngine() }
        }
    }
    @Published var fontSize: Double {
        didSet { defaults.set(fontSize, forKey: Keys.fontSize) }
    }
    @Published var prompterWidth: Double {
        didSet { defaults.set(prompterWidth, forKey: Keys.width) }
    }
    @Published var dimSpokenWords: Bool {
        didSet { defaults.set(dimSpokenWords, forKey: Keys.dimSpoken) }
    }
    /// Wie viele Zeilen über der aktuellen Zeile angezeigt werden.
    @Published var linesBefore: Int {
        didSet { defaults.set(linesBefore, forKey: Keys.linesBefore) }
    }
    /// Wie viele Zeilen unter der aktuellen Zeile angezeigt werden (zum Vorauslesen).
    @Published var linesAfter: Int {
        didSet { defaults.set(linesAfter, forKey: Keys.linesAfter) }
    }

    static let contextLineRange = 0...8

    // MARK: Prompter-Zustand

    @Published private(set) var isPrompting = false
    @Published private(set) var status: PrompterStatus = .idle
    @Published private(set) var script = Script.empty
    /// Index des als Nächstes zu lesenden Worts in `script.spokenWords`.
    @Published private(set) var cursor = 0
    /// Die zuletzt erkannten Wörter (zur Kontrolle im Prompter).
    @Published private(set) var lastHeard = ""

    var isPaused: Bool { status == .paused }

    private let defaults = UserDefaults.standard
    private var matcher = ScriptMatcher(words: [])
    private var transcript = TranscriptBuffer()
    private var engine: SpeechEngine?
    private lazy var panelController = PrompterPanelController(model: self)
    private var cachedLayout: (key: LayoutKey, layout: ScriptLayout)?
    private var scriptVersion = 0

    private enum Keys {
        static let text = "scriptText"
        static let language = "language"
        static let engine = "engine"
        static let fontSize = "fontSize"
        static let width = "prompterWidth"
        static let dimSpoken = "dimSpokenWords"
        static let linesBefore = "linesBefore"
        static let linesAfter = "linesAfter"
    }

    init() {
        text = defaults.string(forKey: Keys.text) ?? AppModel.sampleText
        language = PromptLanguage(rawValue: defaults.string(forKey: Keys.language) ?? "") ?? .german
        engineKind = EngineKind(rawValue: defaults.string(forKey: Keys.engine) ?? "") ?? .speechAnalyzer
        fontSize = defaults.object(forKey: Keys.fontSize) as? Double ?? 34
        prompterWidth = defaults.object(forKey: Keys.width) as? Double ?? 760
        dimSpokenWords = defaults.object(forKey: Keys.dimSpoken) as? Bool ?? true
        linesBefore = Self.clampedContextLines(defaults.object(forKey: Keys.linesBefore) as? Int ?? 1)
        linesAfter = Self.clampedContextLines(defaults.object(forKey: Keys.linesAfter) as? Int ?? 1)
    }

    // MARK: Layout

    static let horizontalPadding: Double = 28

    var lineHeight: Double { (fontSize * 1.32).rounded() }
    var verticalPadding: Double { (fontSize * 0.3).rounded() }
    /// Anzahl der sichtbaren Zeilen: davor + aktuelle + danach.
    var visibleLineCount: Int { linesBefore + 1 + linesAfter }
    var prompterHeight: Double { lineHeight * Double(visibleLineCount) + verticalPadding * 2 }

    static func clampedContextLines(_ value: Int) -> Int {
        min(contextLineRange.upperBound, max(contextLineRange.lowerBound, value))
    }

    private struct LayoutKey: Equatable {
        let scriptVersion: Int
        let width: Double
        let fontSize: Double
    }

    /// Zeilenumbruch des Skripts für die aktuelle Fensterbreite und Schriftgröße.
    var layout: ScriptLayout {
        let key = LayoutKey(scriptVersion: scriptVersion, width: prompterWidth.rounded(), fontSize: fontSize)
        if let cachedLayout, cachedLayout.key == key { return cachedLayout.layout }
        let fonts = PrompterFonts(size: fontSize)
        let layout = ScriptLayout(
            script: script,
            maxWidth: max(100, prompterWidth - Self.horizontalPadding * 2),
            measure: { fonts.width(of: $0, in: $1) },
            spaceWidth: { fonts.spaceWidth(in: $0) }
        )
        cachedLayout = (key, layout)
        return layout
    }

    // MARK: Steuerung

    func startPrompting() {
        script = Script.parse(text)
        scriptVersion += 1
        matcher = ScriptMatcher(words: script.spokenWords)
        cursor = 0
        transcript.clear()
        lastHeard = ""
        isPrompting = true
        panelController.show()
        restartEngine()
    }

    func stopPrompting() {
        isPrompting = false
        panelController.close()
        stopEngine()
        status = .idle
    }

    func togglePause() {
        guard isPrompting else { return }
        switch status {
        case .paused:
            transcript.clear()
            engine?.setPaused(false)
            status = .listening
        case .listening:
            engine?.setPaused(true)
            status = .paused
        default:
            break
        }
    }

    /// Verschiebt die Position manuell um ganze Zeilen (Pfeiltasten).
    func moveLines(_ delta: Int) {
        guard isPrompting, let target = layout.cursor(movingLinesFrom: cursor, by: delta) else { return }
        setCursor(target)
    }

    func restartFromBeginning() {
        guard isPrompting else { return }
        setCursor(0)
    }

    func changeFontSize(by delta: Double) {
        fontSize = min(96, max(16, fontSize + delta))
    }

    private func setCursor(_ newCursor: Int) {
        matcher.reset(toCursor: newCursor)
        cursor = matcher.cursor
        // Alte Wörter sollen die neue Position nicht gleich wieder zurückziehen.
        transcript.clear()
    }

    // MARK: Spracherkennung

    private func restartEngine() {
        stopEngine()
        let engine = engineKind.makeEngine()
        self.engine = engine
        engine.onEvent = { [weak self, weak engine] event in
            Task { @MainActor in
                guard let self, let engine, self.engine === engine else { return }
                self.handle(event)
            }
        }
        status = .preparing("Spracherkennung wird vorbereitet …")
        let locale = language.locale
        let vocabulary = script.contextualVocabulary(limit: 100)
        Task {
            do {
                try await engine.start(locale: locale, contextualStrings: vocabulary)
                guard self.engine === engine else { return }
                self.status = .listening
            } catch {
                guard self.engine === engine else { return }
                self.status = .error(error.localizedDescription)
            }
        }
    }

    private func stopEngine() {
        guard let engine else { return }
        self.engine = nil
        Task { await engine.stop() }
    }

    private func handle(_ event: SpeechEvent) {
        guard isPrompting else { return }
        switch event {
        case .volatile(let text):
            transcript.applyVolatile(text)
        case .final(let text):
            transcript.applyFinal(text)
        case .status(let message):
            if case .preparing = status { status = .preparing(message) }
            return
        case .error(let message):
            status = .error(message)
            return
        }
        guard !isPaused else { return }
        lastHeard = transcript.recentWords.suffix(6).joined(separator: " ")
        if matcher.update(recentWords: transcript.recentWords) {
            cursor = matcher.cursor
        }
    }

    // MARK: Dateien

    func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, UTType(filenameExtension: "md") ?? .plainText]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    func saveFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = "Skript.md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    static let sampleText = """
    # Willkommen bei Promptcript
    Füge hier dein Skript ein. Markdown geht auch: **fett**, *kursiv* und Überschriften.
    Überschriften werden angezeigt, aber nicht als gesprochener Text erwartet.
    Drück auf Play und fang einfach an zu lesen. Der Prompter folgt deiner Stimme.
    Wenn du dich versprichst oder ein Wort auslässt, ist das kein Problem.
    Mit den Pfeiltasten kannst du jederzeit von Hand eine Zeile vor oder zurück springen.
    """
}
