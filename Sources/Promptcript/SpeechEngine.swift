import AVFoundation
import Foundation

/// What a speech recognizer reports to the app.
enum SpeechEvent {
    /// Volatile text, replaced by the next volatile or final result.
    case volatile(String)
    /// Final text of a segment.
    case final(String)
    /// Progress note, e.g. "Loading speech model".
    case status(String)
    case error(String)
}

/// Pluggable speech recognition. New engines (e.g. WhisperKit) only need to conform to this protocol
/// and be added to `EngineKind`.
protocol SpeechEngine: AnyObject {
    /// Called from arbitrary threads.
    var onEvent: ((SpeechEvent) -> Void)? { get set }
    /// Starts the microphone and recognition. `contextualStrings` are vocabulary hints (technical terms from the script).
    func start(locale: Locale, contextualStrings: [String]) async throws
    func setPaused(_ paused: Bool)
    func stop() async
}

enum EngineKind: String, CaseIterable, Identifiable {
    case speechAnalyzer
    case dictation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .speechAnalyzer: "Apple SpeechAnalyzer (recommended)"
        case .dictation: "Apple Dictation (classic)"
        }
    }

    func makeEngine() -> SpeechEngine {
        switch self {
        case .speechAnalyzer: SpeechAnalyzerEngine()
        case .dictation: DictationEngine()
        }
    }
}

struct SpeechEngineError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Requests microphone permission.
func requestMicrophoneAccess() async throws {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized:
        return
    case .notDetermined:
        if await AVCaptureDevice.requestAccess(for: .audio) { return }
    default:
        break
    }
    throw SpeechEngineError(message: "No access to the microphone. Please allow it in System Settings → Privacy & Security → Microphone.")
}

/// Converts microphone buffers into the format the recognizer expects.
final class AudioBufferConverter {
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat

    init(from input: AVAudioFormat, to output: AVAudioFormat) throws {
        guard let converter = AVAudioConverter(from: input, to: output) else {
            throw SpeechEngineError(message: "The microphone's audio format is not supported.")
        }
        converter.primeMethod = .none
        self.converter = converter
        self.outputFormat = output
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if buffer.format == outputFormat { return buffer }
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 16
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return nil }

        var consumed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, output.frameLength > 0 else { return nil }
        return output
    }
}
