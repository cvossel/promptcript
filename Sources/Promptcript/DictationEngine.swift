import AVFoundation
import Foundation
import Speech

/// Classic speech recognition via `SFSpeechRecognizer`.
/// Fallback in case SpeechAnalyzer causes problems. Supports vocabulary hints reliably.
final class DictationEngine: SpeechEngine {
    var onEvent: ((SpeechEvent) -> Void)?

    private let audioEngine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var contextualStrings: [String] = []
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var isStopped = false
    /// Incremented per recognition task so that callbacks from finished tasks are ignored.
    private var generation = 0

    func start(locale: Locale, contextualStrings: [String]) async throws {
        try await requestMicrophoneAccess()

        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard status == .authorized else {
            throw SpeechEngineError(message: "Speech recognition is not allowed. Please allow it in System Settings → Privacy & Security → Speech Recognition.")
        }
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw SpeechEngineError(message: "Speech recognition for \(locale.identifier) is currently unavailable.")
        }
        self.recognizer = recognizer
        // SFSpeechRecognizer only handles a limited number of hints well.
        self.contextualStrings = Array(contextualStrings.prefix(100))

        startRecognitionTask()

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw SpeechEngineError(message: "No microphone found.")
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

    /// A recognition task ends after a pause in speech or after about a minute.
    /// A new one is then started seamlessly.
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
                // Typically a time limit or "no speech detected" – just restart.
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
