import AppKit
import Combine
import SwiftUI

/// Rahmenloses Fenster, das immer im Vordergrund bleibt und auf allen Desktops sichtbar ist.
final class PrompterPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Lässt das Fenster an jeder Stelle des Inhalts verschieben.
final class DraggableHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool { true }
}

/// Erzeugt und verwaltet das Prompter-Fenster: Position unter der Kamera, Größe, Tastatur.
@MainActor
final class PrompterPanelController: NSObject, NSWindowDelegate {
    private unowned let model: AppModel
    private var panel: PrompterPanel?
    private var keyMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    private let originKey = "prompterOrigin"

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func close() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> PrompterPanel {
        let size = NSSize(width: model.prompterWidth, height: model.prompterHeight)
        let panel = PrompterPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        // Bei Bildschirmaufnahmen unsichtbar, damit der Prompter nicht im Video landet.
        panel.sharingType = .none

        let hostingView = DraggableHostingView(rootView: PrompterView().environmentObject(model))
        hostingView.sizingOptions = []
        panel.contentView = hostingView

        panel.setFrameOrigin(initialOrigin(for: size))
        updateSizeLimits(panel)
        panel.delegate = self

        // Höhe folgt Schriftgröße und Zeilenzahl, die Oberkante bleibt dabei unter der Kamera.
        Publishers.Merge3(
            model.$fontSize.dropFirst().map { _ in () },
            model.$linesBefore.dropFirst().map { _ in () },
            model.$linesAfter.dropFirst().map { _ in () }
        )
            .sink { [weak self, weak panel] _ in
                DispatchQueue.main.async {
                    guard let self, let panel else { return }
                    self.applyHeight(to: panel)
                }
            }
            .store(in: &cancellables)

        installKeyMonitor(for: panel)
        return panel
    }

    /// Gespeicherte Position oder oben mittig direkt unter der Menüleiste (also unter der Kamera).
    private func initialOrigin(for size: NSSize) -> NSPoint {
        if let stored = UserDefaults.standard.string(forKey: originKey) {
            let point = NSPointFromString(stored)
            let frame = NSRect(origin: point, size: size)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) {
                return point
            }
        }
        let screen = NSScreen.screens.first ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 4)
    }

    private func updateSizeLimits(_ panel: NSPanel) {
        let height = model.prompterHeight
        panel.contentMinSize = NSSize(width: 320, height: height)
        panel.contentMaxSize = NSSize(width: 4000, height: height)
    }

    private func applyHeight(to panel: NSPanel) {
        updateSizeLimits(panel)
        var frame = panel.frame
        let top = frame.maxY
        frame.size.height = model.prompterHeight
        frame.origin.y = top - frame.size.height
        panel.setFrame(frame, display: true, animate: false)
    }

    // MARK: NSWindowDelegate

    func windowDidResize(_ notification: Notification) {
        guard let panel else { return }
        let width = panel.frame.width
        if abs(width - model.prompterWidth) > 0.5 {
            model.prompterWidth = width
        }
    }

    func windowDidMove(_ notification: Notification) {
        guard let panel else { return }
        UserDefaults.standard.set(NSStringFromPoint(panel.frame.origin), forKey: originKey)
    }

    // MARK: Tastatur

    private func installKeyMonitor(for panel: NSPanel) {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak panel] event in
            guard let self, let panel, event.window === panel else { return event }
            return self.handleKey(event) ? nil : event
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 53: // Esc
            model.stopPrompting()
        case 49: // Leertaste
            model.togglePause()
        case 125, 124: // Pfeil runter / rechts
            model.moveLines(1)
        case 126, 123: // Pfeil hoch / links
            model.moveLines(-1)
        default:
            switch event.charactersIgnoringModifiers {
            case "+", "=": model.changeFontSize(by: 2)
            case "-": model.changeFontSize(by: -2)
            case "0": model.restartFromBeginning()
            default: return false
            }
        }
        return true
    }
}
