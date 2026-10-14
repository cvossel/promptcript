# Promptcript

A teleprompter for macOS that follows your voice. It shows the line you are currently reading,
plus a configurable number of lines above and below it (default: one each). Speech recognition runs entirely on your Mac.

## Build and run

```bash
./build.sh --open
```

The app is then located at `build/Promptcript.app` and can be dragged into the Applications folder.
On first launch, macOS asks for microphone access. The first time you press Play, the speech
model is also loaded once.

Requirements: macOS 26 and the Xcode Command Line Tools (`xcode-select --install`).

## Usage

1. Paste your text into the editor (Markdown works: `**bold**`, `*italic*`, `# Heading`, lists).
2. Pick a language: at the bottom of the window or in the **Language** menu.
3. **Play** (⌘↩) opens the prompter at the top center, right below the camera.
4. Read. The prompter scrolls along.

Headings are displayed, but they are not expected to be spoken. Useful as chapter markers.

In the prompter window:

| Key             | Action                       |
| --------------- | ---------------------------- |
| Space           | Pause / Resume               |
| ↓ / →           | Next line                    |
| ↑ / ←           | Previous line                |
| + / −           | Larger / smaller font        |
| 0               | Back to start                |
| Esc             | Stop prompter                |

In **Settings** (⌘, or the gear icon in the editor) you set how many lines are shown before and
after the current line (0–8 each). More lines after help you read ahead when recognition
lags behind. You can also change this live via the prompter's right-click menu.

The window can be grabbed and moved anywhere, resized in width at its edges,
and remembers its position. Right-click opens a menu. The dot in the top right shows the status
(green = listening, yellow = loading/paused, red = error).

The prompter is intentionally invisible in screen recordings, so it does not end up in your video.

## How tracking works

- **Speech recognition:** Apple's `SpeechAnalyzer` (macOS 26). In the **Prompter → Speech Recognition**
  menu you can switch to Apple's classic recognizer. Additional engines (e.g. WhisperKit)
  can be added via the `SpeechEngine` protocol.
- **Technical terms:** Words from the script that look like technical terms (CamelCase, abbreviations,
  English-looking words) are passed to the recognizer as vocabulary hints.
- **Matching** (`ScriptMatcher`): The last eight recognized words are fuzzily matched against the text
  around the current position (Smith-Waterman alignment). This tolerates misrecognized
  words, filler words, skipped words, digressions, and terms recognized as split or joined.
  The prompter jumps forward easily, but only jumps back on a clear match,
  e.g. when you restart a sentence.

## Development

```bash
./test.sh                                                     # Tests
swift run PromptcriptBench script.md recording.aiff de-DE     # Run an audio file through recognition + matching
```

Test recordings can be created with e.g. `say -v Samantha -o test.aiff "…"` (or `say -v Anna` for German).
`PromptcriptBench` lets you check error tolerance without a microphone and tune the values in
`ScriptMatcher.Configuration`.
