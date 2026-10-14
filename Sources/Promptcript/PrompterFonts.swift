import AppKit
import PromptcriptCore

/// Schriften des Prompters. Dieselben NSFonts werden zum Messen (Zeilenumbruch)
/// und zum Zeichnen verwendet, damit beides exakt zusammenpasst.
struct PrompterFonts {
    let size: Double

    func font(for style: TokenStyle, in kind: BlockKind) -> NSFont {
        if kind.isHeading {
            return NSFont.systemFont(ofSize: size * 0.62, weight: .semibold)
        }
        if style.contains(.code) {
            return NSFont.monospacedSystemFont(ofSize: size * 0.92, weight: .medium)
        }
        var font = NSFont.systemFont(ofSize: size, weight: style.contains(.bold) ? .heavy : .medium)
        if style.contains(.italic) {
            font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        }
        return font
    }

    func width(of token: ScriptToken, in kind: BlockKind) -> Double {
        let font = font(for: token.style, in: kind)
        return (token.text as NSString).size(withAttributes: [.font: font]).width
    }

    func spaceWidth(in kind: BlockKind) -> Double {
        (" " as NSString).size(withAttributes: [.font: font(for: [], in: kind)]).width
    }
}
