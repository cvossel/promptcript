import SwiftUI

/// Einstellungen (⌘,): Darstellung des Prompters.
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("Sichtbare Zeilen") {
                Stepper(value: $model.linesBefore, in: AppModel.contextLineRange) {
                    LabeledContent("Zeilen davor", value: "\(model.linesBefore)")
                }
                .help("Bereits gelesene Zeilen über der aktuellen Zeile")
                Stepper(value: $model.linesAfter, in: AppModel.contextLineRange) {
                    LabeledContent("Zeilen danach", value: "\(model.linesAfter)")
                }
                .help("Kommende Zeilen unter der aktuellen Zeile, zum Vorauslesen")
            }

            Section("Schrift") {
                LabeledContent("Größe") {
                    HStack {
                        Slider(value: $model.fontSize, in: 16...96, step: 1)
                        Text("\(Int(model.fontSize)) pt")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                Toggle("Gesprochenes abdunkeln", isOn: $model.dimSpokenWords)
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .fixedSize()
    }
}
