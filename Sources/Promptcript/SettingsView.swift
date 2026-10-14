import SwiftUI

/// Settings (⌘,): prompter appearance.
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("Visible Lines") {
                Stepper(value: $model.linesBefore, in: AppModel.contextLineRange) {
                    LabeledContent("Lines before", value: "\(model.linesBefore)")
                }
                .help("Already read lines above the current line")
                Stepper(value: $model.linesAfter, in: AppModel.contextLineRange) {
                    LabeledContent("Lines after", value: "\(model.linesAfter)")
                }
                .help("Upcoming lines below the current line, for reading ahead")
            }

            Section("Font") {
                LabeledContent("Size") {
                    HStack {
                        Slider(value: $model.fontSize, in: 16...96, step: 1)
                        Text("\(Int(model.fontSize)) pt")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                Toggle("Dim spoken words", isOn: $model.dimSpokenWords)
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .fixedSize()
    }
}
