import SwiftUI

@main
struct PromptcriptApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("Promptcript", id: "editor") {
            EditorView()
                .environmentObject(model)
        }
        .defaultSize(width: 860, height: 560)
        .commands {
            PromptcriptCommands(model: model)
        }

        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }
}

struct PromptcriptCommands: Commands {
    @ObservedObject var model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Öffnen …") { model.openFile() }
                .keyboardShortcut("o")
            Button("Sichern unter …") { model.saveFile() }
                .keyboardShortcut("s")
        }

        CommandMenu("Sprache") {
            Picker("Sprache", selection: $model.language) {
                ForEach(PromptLanguage.allCases) { language in
                    Text(language.title).tag(language)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }

        CommandMenu("Prompter") {
            Button(model.isPrompting ? "Neu starten" : "Starten") { model.startPrompting() }
                .keyboardShortcut(.return, modifiers: .command)
            Button(model.isPaused ? "Fortsetzen" : "Pause") { model.togglePause() }
                .disabled(!model.isPrompting)
            Button("Beenden") { model.stopPrompting() }
                .disabled(!model.isPrompting)
            Divider()
            Button("Eine Zeile vor") { model.moveLines(1) }
                .disabled(!model.isPrompting)
            Button("Eine Zeile zurück") { model.moveLines(-1) }
                .disabled(!model.isPrompting)
            Button("Zum Anfang") { model.restartFromBeginning() }
                .disabled(!model.isPrompting)
            Divider()
            Picker("Spracherkennung", selection: $model.engineKind) {
                ForEach(EngineKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
        }
    }
}
