import AVFoundation
import Foundation
import Speech

/// Speech recognition with Apple's `SpeechAnalyzer`/`SpeechTranscriber` (macOS 26).
/// Runs entirely on device and delivers fast volatile results.
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
            throw SpeechEngineError(message: "SpeechAnalyzer is not available on this Mac. Please choose the classic recognizer in the Prompter menu.")
        }
        guard let supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw SpeechEngineError(message: "The language \(locale.identifier) is not supported by SpeechAnalyzer.")
        }

        let transcriber = SpeechTranscriber(
            locale: supportedLocale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults, .fastResults],
            attributeOptions: []
        )

        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            onEvent?(.status("Downloading speech model …"))
            try await request.downloadAndInstall()
        }

        let analyzer = SpeechAnalyzer(
            modules: [transcriber],
            options: .init(priority: .userInitiated, modelRetention: .processLifetime)
        )
        self.analyzer = analyzer

        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw SpeechEngineError(message: "No suitable audio format found for speech recognition.")
        }
        onEvent?(.status("Loading speech model …"))
        try await analyzer.prepareToAnalyze(in: analyzerFormat)

        if !contextualStrings.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings[.general] = contextualStrings
            // Not every model supports vocabulary hints – in that case, do without.
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
                self.onEvent?(.error("Speech recognition stopped: \(error.localizedDescription)"))
            }
        }

        try await analyzer.start(inputSequence: stream)
        try startAudio(analyzerFormat: analyzerFormat, continuation: continuation)
    }

    private func startAudio(analyzerFormat: AVAudioFormat, continuation: AsyncStream<AnalyzerInput>.Continuation) throws {
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw SpeechEngineError(message: "No microphone found.")
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
