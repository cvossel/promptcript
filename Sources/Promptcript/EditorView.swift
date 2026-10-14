import SwiftUI

/// Main window: paste a script, pick a language, press Play.
struct EditorView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: $model.text)
                .font(.system(size: 14, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(12)
                .background(Color(nsColor: .textBackgroundColor))

            Divider()

            HStack(spacing: 18) {
                Picker("Language", selection: $model.language) {
                    ForEach(PromptLanguage.allCases) { language in
                        Text(language.title).tag(language)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 180)
                .help("Speech recognition language")

                HStack(spacing: 6) {
                    Image(systemName: "textformat.size.smaller")
                    Slider(value: $model.fontSize, in: 16...96, step: 1)
                        .frame(width: 120)
                    Image(systemName: "textformat.size.larger")
                }
                .foregroundStyle(.secondary)
                .help("Prompter font size")

                Toggle("Dim spoken words", isOn: $model.dimSpokenWords)
                    .toggleStyle(.checkbox)

                SettingsLink {
                    Image(systemName: "gearshape")
                }
                .help("Settings (⌘,)")

                Spacer()

                if model.isPrompting {
                    Button("Stop") { model.stopPrompting() }
                        .keyboardShortcut(.escape, modifiers: [])
                }
                Button {
                    model.startPrompting()
                } label: {
                    Label(model.isPrompting ? "Restart" : "Play", systemImage: "play.fill")
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: .command)
                .help("Start prompter (⌘↩)")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(minWidth: 700, minHeight: 420)
    }
}
