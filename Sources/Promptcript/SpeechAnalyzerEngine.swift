import AVFoundation
import Foundation
import Speech

/// Spracherkennung mit Apples `SpeechAnalyzer`/`SpeechTranscriber` (macOS 26).
/// Läuft komplett auf dem Gerät und liefert schnelle vorläufige Ergebnisse.
final class SpeechAnalyzerEngine: SpeechEngine {
    var onEvent: ((SpeechEvent) -> Void)?

    private let audioEngine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var isStopped = false

    func start(locale: Locale, contextualStrings: [String]) async throws {
        try await requestMicrophoneAccess()

        guard SpeechTranscriber.isAvailable else {
            throw SpeechEngineError(message: "SpeechAnalyzer ist auf diesem Mac nicht verfügbar. Bitte im Menü „Prompter“ die klassische Erkennung wählen.")
        }
        guard let supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw SpeechEngineError(message: "Die Sprache \(locale.identifier) wird von SpeechAnalyzer nicht unterstützt.")
        }

        let transcriber = SpeechTranscriber(
            locale: supportedLocale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults, .fastResults],
            attributeOptions: []
        )

        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            onEvent?(.status("Sprachmodell wird heruntergeladen …"))
            try await request.downloadAndInstall()
        }

        let analyzer = SpeechAnalyzer(
            modules: [transcriber],
            options: .init(priority: .userInitiated, modelRetention: .processLifetime)
        )
        self.analyzer = analyzer

        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw SpeechEngineError(message: "Kein passendes Audioformat für die Spracherkennung gefunden.")
        }
        onEvent?(.status("Sprachmodell wird geladen …"))
        try await analyzer.prepareToAnalyze(in: analyzerFormat)

        if !contextualStrings.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings[.general] = contextualStrings
            // Nicht jedes Modell unterstützt Vokabelhinweise – dann eben ohne.
            try? await analyzer.setContext(context)
        }

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        inputContinuation = continuation

        resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    self?.onEvent?(result.isFinal ? .final(text) : .volatile(text))
                }
            } catch {
                guard let self, !self.isStopped else { return }
                self.onEvent?(.error("Spracherkennung abgebrochen: \(error.localizedDescription)"))
            }
        }

        try await analyzer.start(inputSequence: stream)
        try startAudio(analyzerFormat: analyzerFormat, continuation: continuation)
    }

    private func startAudio(analyzerFormat: AVAudioFormat, continuation: AsyncStream<AnalyzerInput>.Continuation) throws {
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw SpeechEngineError(message: "Kein Mikrofon gefunden.")
        }
        let converter = try AudioBufferConverter(from: inputFormat, to: analyzerFormat)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { buffer, _ in
            if let converted = converter.convert(buffer) {
                continuation.yield(AnalyzerInput(buffer: converted))
            }
        }
        audioEngine.prepare()
        try audioEngine.start()
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
        inputContinuation?.finish()
        inputContinuation = nil
        await analyzer?.cancelAndFinishNow()
        analyzer = nil
        resultsTask?.cancel()
        resultsTask = nil
    }
}
