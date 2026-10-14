import AVFoundation
import Foundation
import Speech

/// Klassische Spracherkennung über `SFSpeechRecognizer`.
/// Alternative, falls SpeechAnalyzer Probleme macht. Unterstützt Vokabelhinweise zuverlässig.
final class DictationEngine: SpeechEngine {
    var onEvent: ((SpeechEvent) -> Void)?

    private let audioEngine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var contextualStrings: [String] = []
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var isStopped = false
    /// Zählt Erkennungsaufgaben hoch, damit Rückmeldungen beendeter Aufgaben ignoriert werden.
    private var generation = 0

    func start(locale: Locale, contextualStrings: [String]) async throws {
        try await requestMicrophoneAccess()

        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard status == .authorized else {
            throw SpeechEngineError(message: "Spracherkennung nicht erlaubt. Bitte in Systemeinstellungen → Datenschutz & Sicherheit → Spracherkennung erlauben.")
        }
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw SpeechEngineError(message: "Die Spracherkennung für \(locale.identifier) ist gerade nicht verfügbar.")
        }
        self.recognizer = recognizer
        // SFSpeechRecognizer verarbeitet nur eine begrenzte Zahl an Hinweisen sinnvoll.
        self.contextualStrings = Array(contextualStrings.prefix(100))

        startRecognitionTask()

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw SpeechEngineError(message: "Kein Mikrofon gefunden.")
        }
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.lock.lock()
            let request = self.request
            self.lock.unlock()
            request?.append(buffer)
        }
        audioEngine.prepare()
        try audioEngine.start()
    }

    /// Eine Erkennungsaufgabe endet nach einer Sprechpause oder ca. einer Minute.
    /// Dann wird nahtlos eine neue gestartet.
    private func startRecognitionTask() {
        guard !isStopped, let recognizer else { return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.addsPunctuation = false
        request.contextualStrings = contextualStrings
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        lock.lock()
        self.request?.endAudio()
        self.request = request
        generation += 1
        let taskGeneration = generation
        lock.unlock()

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self, !self.isStopped, self.isCurrent(taskGeneration) else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                if result.isFinal {
                    self.onEvent?(.final(text))
                    self.startRecognitionTask()
                    return
                }
                self.onEvent?(.volatile(text))
            }
            if error != nil {
                // Typisch: Zeitlimit oder „keine Sprache erkannt“ – einfach neu starten.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    if self.isCurrent(taskGeneration) { self.startRecognitionTask() }
                }
            }
        }
    }

    private func isCurrent(_ taskGeneration: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return taskGeneration == generation
    }

    func setPaused(_ paused: Bool) {
        if paused {
            audioEngine.pause()
        } else {
            try? audioEngine.start()
        }
    }

    func stop() async {
        isStopped = true
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        lock.withLock {
            request?.endAudio()
            request = nil
        }
        task?.cancel()
        task = nil
    }
}
