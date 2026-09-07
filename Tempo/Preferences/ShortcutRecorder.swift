import AppKit
import SwiftUI

/// Campo que captura una combinación de teclas para asignarla a un atajo global.
///
/// Al pulsarlo entra en modo de grabación: la siguiente combinación con al menos ⌘, ⌥ o ⌃
/// se convierte en el nuevo atajo. Esc cancela y ⌫ restablece el valor de fábrica.
struct ShortcutRecorder: NSViewRepresentable {

    @Binding var shortcut: GlobalShortcut
    /// Valor al que vuelve con ⌫.
    let fallback: GlobalShortcut
    /// Se consulta antes de aceptar, para no permitir dos atajos iguales.
    var isAvailable: (GlobalShortcut) -> Bool = { _ in true }

    func makeNSView(context: Context) -> ShortcutRecorderView {
        let view = ShortcutRecorderView()
        view.shortcut = shortcut
        view.fallback = fallback
        view.isAvailable = isAvailable
        view.onChange = { shortcut = $0 }
        return view
    }

    func updateNSView(_ view: ShortcutRecorderView, context: Context) {
        view.shortcut = shortcut
        view.fallback = fallback
        view.isAvailable = isAvailable
        view.needsDisplay = true
    }
}

final class ShortcutRecorderView: NSView {

    var shortcut: GlobalShortcut = .defaultFullScreen
    var fallback: GlobalShortcut = .defaultFullScreen
    var isAvailable: (GlobalShortcut) -> Bool = { _ in true }
    var onChange: ((GlobalShortcut) -> Void)?

    private var isRecording = false {
        didSet {
            needsDisplay = true
            discardCursorRects()
            window?.invalidateCursorRects(for: self)
        }
    }
    private var isHovered = false { didSet { needsDisplay = true } }
    private var rejectionMessage: String?
    private var trackingArea: NSTrackingArea?

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 150, height: 26) }

    // MARK: - Interacción

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseDown(with event: NSEvent) {
        rejectionMessage = nil
        isRecording.toggle()
        if isRecording {
            window?.makeFirstResponder(self)
        }
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Mientras se graba, la combinación pertenece al campo y no debe activar menús.
        guard isRecording else { return false }
        return handle(event)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        if !handle(event) {
            NSSound.beep()
        }
    }

    private func handle(_ event: NSEvent) -> Bool {
        // Esc cancela la grabación.
        if event.keyCode == 53 {
            isRecording = false
            rejectionMessage = nil
            return true
        }

        // ⌫ restablece el atajo de fábrica.
        if event.keyCode == 51 {
            shortcut = fallback
            onChange?(fallback)
            isRecording = false
            rejectionMessage = nil
            return true
        }

        let candidate = GlobalShortcut(keyCode: Int(event.keyCode),
                                       modifiers: event.modifierFlags)

        guard candidate.isValid else {
            rejectionMessage = "Añade ⌘, ⌥ o ⌃"
            needsDisplay = true
            return false
        }

        guard isAvailable(candidate) else {
            rejectionMessage = "Ya está en uso"
            needsDisplay = true
            return false
        }

        shortcut = candidate
        onChange?(candidate)
        isRecording = false
        rejectionMessage = nil
        return true
    }

    // MARK: - Dibujo

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = CGPath(roundedRect: rect, cornerWidth: 6, cornerHeight: 6, transform: nil)

        context.addPath(path)
        let background: NSColor = isRecording
            ? .controlAccentColor.withAlphaComponent(0.16)
            : (isHovered ? .controlColor.blended(withFraction: 0.1, of: .labelColor) ?? .controlColor : .controlColor)
        context.setFillColor(background.cgColor)
        context.fillPath()

        context.addPath(path)
        context.setStrokeColor((isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor)
        context.setLineWidth(isRecording ? 1.5 : 1)
        context.strokePath()

        let text: String
        let color: NSColor
        if let rejectionMessage {
            text = rejectionMessage
            color = .systemRed
        } else if isRecording {
            text = "Pulsa la combinación…"
            color = .secondaryLabelColor
        } else {
            text = shortcut.display
            color = .labelColor
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: isRecording || rejectionMessage != nil ? 11 : 13,
                                     weight: .medium),
            .foregroundColor: color
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let size = attributed.size()
        attributed.draw(at: CGPoint(x: bounds.midX - size.width / 2,
                                    y: bounds.midY - size.height / 2))
    }
}
