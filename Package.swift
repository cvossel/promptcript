// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Promptcript",
    platforms: [.macOS(.v26)],
    targets: [
        // Platform-independent logic: Markdown parsing, line wrapping, matching speech ↔ script.
        .target(
            name: "PromptcriptCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // The macOS app (SwiftUI + AppKit + speech recognition).
        .executableTarget(
            name: "Promptcript",
            dependencies: ["PromptcriptCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Developer tool: audio file → SpeechAnalyzer → matching, no microphone needed.
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
