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
            Button("Open …") { model.openFile() }
                .keyboardShortcut("o")
            Button("Save As …") { model.saveFile() }
                .keyboardShortcut("s")
        }

        CommandMenu("Language") {
            Picker("Language", selection: $model.language) {
                ForEach(PromptLanguage.allCases) { language in
                    Text(language.title).tag(language)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }

        CommandMenu("Prompter") {
            Button(model.isPrompting ? "Restart" : "Start") { model.startPrompting() }
                .keyboardShortcut(.return, modifiers: .command)
            Button(model.isPaused ? "Resume" : "Pause") { model.togglePause() }
                .disabled(!model.isPrompting)
            Button("Stop") { model.stopPrompting() }
                .disabled(!model.isPrompting)
            Divider()
            Button("Next Line") { model.moveLines(1) }
                .disabled(!model.isPrompting)
            Button("Previous Line") { model.moveLines(-1) }
                .disabled(!model.isPrompting)
            Button("Back to Start") { model.restartFromBeginning() }
                .disabled(!model.isPrompting)
            Divider()
            Picker("Speech Recognition", selection: $model.engineKind) {
                ForEach(EngineKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
        }
    }
}
