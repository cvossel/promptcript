import AVFoundation
import Foundation

/// Was eine Spracherkennung an die App meldet.
enum SpeechEvent {
    /// Vorläufiger Text, wird vom nächsten vorläufigen oder endgültigen Ergebnis ersetzt.
    case volatile(String)
    /// Endgültiger Text eines Abschnitts.
    case final(String)
    /// Hinweis zum Fortschritt, z. B. „Sprachmodell wird geladen“.
    case status(String)
    case error(String)
}

/// Austauschbare Spracherkennung. Neue Engines (z. B. WhisperKit) müssen nur dieses Protokoll erfüllen
/// und in `EngineKind` eingetragen werden.
protocol SpeechEngine: AnyObject {
    /// Wird von beliebigen Threads aufgerufen.
    var onEvent: ((SpeechEvent) -> Void)? { get set }
    /// Startet Mikrofon und Erkennung. `contextualStrings` sind Vokabelhinweise (Fachbegriffe aus dem Skript).
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
        case .speechAnalyzer: "Apple SpeechAnalyzer (empfohlen)"
        case .dictation: "Apple Diktat (klassisch)"
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

/// Fragt die Mikrofonberechtigung an.
func requestMicrophoneAccess() async throws {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized:
        return
    case .notDetermined:
        if await AVCaptureDevice.requestAccess(for: .audio) { return }
    default:
        break
    }
    throw SpeechEngineError(message: "Kein Zugriff aufs Mikrofon. Bitte in Systemeinstellungen → Datenschutz & Sicherheit → Mikrofon erlauben.")
}

/// Wandelt Mikrofonpuffer in das Format, das die Erkennung erwartet.
final class AudioBufferConverter {
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat

    init(from input: AVAudioFormat, to output: AVAudioFormat) throws {
        guard let converter = AVAudioConverter(from: input, to: output) else {
            throw SpeechEngineError(message: "Audioformat des Mikrofons wird nicht unterstützt.")
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
