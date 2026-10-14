import PromptcriptCore
import SwiftUI

/// Der eigentliche Prompter: die aktuelle Zeile plus einstellbar viele Zeilen davor und danach.
struct PrompterView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let layout = model.layout
        let lineHeight = model.lineHeight
        let current = layout.lineIndex(forCursor: model.cursor)
        let before = model.linesBefore
        let visible = visibleRange(around: current, count: layout.lines.count)

        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black)

            if layout.lines.isEmpty {
                Text("Kein Text – bitte im Editor ein Skript einfügen.")
                    .font(.system(size: 18))
                    .foregroundStyle(.gray)
            } else {
                ZStack(alignment: .top) {
                    ForEach(visible, id: \.self) { index in
                        lineText(layout.lines[index], isCurrent: index == current)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .frame(height: lineHeight)
                            .offset(y: CGFloat(index - current + before) * lineHeight)
                    }
                }
                .frame(height: lineHeight * CGFloat(model.visibleLineCount), alignment: .top)
                .clipped()
                .padding(.horizontal, AppModel.horizontalPadding)
                .animation(.easeInOut(duration: 0.35), value: current)
            }

            statusOverlay
        }
        .contextMenu { contextMenu }
    }

    /// Eine Zeile Puffer oben und unten, damit beim Scrollen Zeilen von außen hereingleiten.
    private func visibleRange(around current: Int, count: Int) -> [Int] {
        guard count > 0 else { return [] }
        let lower = max(0, current - model.linesBefore - 1)
        let upper = min(count - 1, current + model.linesAfter + 1)
        return Array(lower...upper)
    }

    private func lineText(_ line: DisplayLine, isCurrent: Bool) -> Text {
        let fonts = PrompterFonts(size: model.fontSize)
        var result = AttributedString()
        for (index, token) in line.tokens.enumerated() {
            var piece = AttributedString(index < line.tokens.count - 1 ? token.text + " " : token.text)
            piece.font = Font(fonts.font(for: token.style, in: line.kind) as CTFont)
            piece.foregroundColor = color(for: token, in: line, isCurrent: isCurrent)
            result += piece
        }
        return Text(result)
    }

    private func color(for token: ScriptToken, in line: DisplayLine, isCurrent: Bool) -> Color {
        if line.kind.isHeading {
            return Color.orange.opacity(isCurrent ? 0.95 : 0.55)
        }
        guard isCurrent else { return Color.white.opacity(0.32) }
        let isSpoken = !token.spokenRange.isEmpty
            ? token.spokenRange.upperBound <= model.cursor
            : (line.spokenRange.map { $0.lowerBound < model.cursor } ?? false)
        if model.dimSpokenWords && isSpoken {
            return Color.white.opacity(0.5)
        }
        return Color.white
    }

    @ViewBuilder
    private var statusOverlay: some View {
        VStack {
            HStack {
                Spacer()
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                    .help(statusHelp)
            }
            Spacer()
            if let message = statusMessage {
                Text(message)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
            }
        }
        .padding(10)
        .allowsHitTesting(true)
    }

    private var statusColor: Color {
        switch model.status {
        case .listening: .green
        case .preparing, .paused: .yellow
        case .error: .red
        case .idle: .gray
        }
    }

    private var statusMessage: String? {
        switch model.status {
        case .preparing(let message): message
        case .paused: "Pausiert – Leertaste zum Fortsetzen"
        case .error(let message): message
        case .listening, .idle: nil
        }
    }

    private var statusHelp: String {
        switch model.status {
        case .listening: "Hört zu. Zuletzt erkannt: \(model.lastHeard)"
        default: statusMessage ?? ""
        }
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button(model.isPaused ? "Fortsetzen" : "Pause") { model.togglePause() }
        Button("Eine Zeile vor") { model.moveLines(1) }
        Button("Eine Zeile zurück") { model.moveLines(-1) }
        Button("Zum Anfang") { model.restartFromBeginning() }
        Divider()
        Button("Schrift größer") { model.changeFontSize(by: 2) }
        Button("Schrift kleiner") { model.changeFontSize(by: -2) }
        Picker("Zeilen davor", selection: $model.linesBefore) {
            ForEach(AppModel.contextLineRange, id: \.self) { Text("\($0)").tag($0) }
        }
        Picker("Zeilen danach", selection: $model.linesAfter) {
            ForEach(AppModel.contextLineRange, id: \.self) { Text("\($0)").tag($0) }
        }
        Divider()
        Button("Prompter beenden") { model.stopPrompting() }
    }
}
