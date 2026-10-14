import SwiftUI

/// Hauptfenster: Skript einfügen, Sprache wählen, Play drücken.
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
                Picker("Sprache", selection: $model.language) {
                    ForEach(PromptLanguage.allCases) { language in
                        Text(language.title).tag(language)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 180)
                .help("Sprache der Spracherkennung")

                HStack(spacing: 6) {
                    Image(systemName: "textformat.size.smaller")
                    Slider(value: $model.fontSize, in: 16...96, step: 1)
                        .frame(width: 120)
                    Image(systemName: "textformat.size.larger")
                }
                .foregroundStyle(.secondary)
                .help("Schriftgröße im Prompter")

                Toggle("Gesprochenes abdunkeln", isOn: $model.dimSpokenWords)
                    .toggleStyle(.checkbox)

                SettingsLink {
                    Image(systemName: "gearshape")
                }
                .help("Einstellungen (⌘,)")

                Spacer()

                if model.isPrompting {
                    Button("Stopp") { model.stopPrompting() }
                        .keyboardShortcut(.escape, modifiers: [])
                }
                Button {
                    model.startPrompting()
                } label: {
                    Label(model.isPrompting ? "Neu starten" : "Play", systemImage: "play.fill")
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: .command)
                .help("Prompter starten (⌘↩)")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(minWidth: 700, minHeight: 420)
    }
}
