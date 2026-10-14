// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Promptcript",
    platforms: [.macOS(.v26)],
    targets: [
        // Plattformunabhängige Logik: Markdown-Parsing, Zeilenumbruch, Abgleich Sprache ↔ Skript.
        .target(
            name: "PromptcriptCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Die macOS-App (SwiftUI + AppKit + Spracherkennung).
        .executableTarget(
            name: "Promptcript",
            dependencies: ["PromptcriptCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Entwicklerwerkzeug: Audiodatei → SpeechAnalyzer → Abgleich, ohne Mikrofon.
        .executableTarget(
            name: "PromptcriptBench",
            dependencies: ["PromptcriptCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "PromptcriptCoreTests",
            dependencies: ["PromptcriptCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
