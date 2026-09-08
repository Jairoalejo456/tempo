import AppKit

/// Muestra una capa a pantalla completa (una por monitor) para que el usuario arrastre
/// y seleccione la región que quiere capturar.
///
/// Devuelve el rectángulo en coordenadas globales de AppKit junto con la pantalla a la que
/// pertenece. Cancelar con Esc, con clic derecho o con un clic sin arrastre no captura nada.
final class RegionSelectionController {

    private var windows: [SelectionOverlayWindow] = []
    private var completion: ((NSScreen, CGRect)?) -> Void = { _ in }
    private var isFinished = false

    var isActive: Bool { !windows.isEmpty }

    /// - Parameter completion: recibe `nil` si el usuario cancela.
    func begin(completion: @escaping ((NSScreen, CGRect)?) -> Void) {
        guard windows.isEmpty else { return }
        self.completion = completion
        isFinished = false

        for screen in NSScreen.screens {
            let window = SelectionOverlayWindow(screen: screen)
            window.selectionDelegate = self
            window.orderFrontRegardless()
            windows.append(window)
        }

        NSApp.activate(ignoringOtherApps: true)
        windows.first?.makeKey()
    }

    fileprivate func finish(screen: NSScreen?, rect: CGRect?) {
        guard !isFinished else { return }
        isFinished = true

        let result: (NSScreen, CGRect)?
        if let screen, let rect, rect.width >= 2, rect.height >= 2 {
            result = (screen, rect)
        } else {
            result = nil
        }

        tearDown()

        // Se espera un ciclo de ejecución para que las ventanas desaparezcan de la pantalla
        // antes de disparar la captura.
        DispatchQueue.main.async { [completion] in
            completion(result)
        }
    }

    private func tearDown() {
        for window in windows {
            window.selectionDelegate = nil
            window.orderOut(nil)
        }
        windows.removeAll()
        NSCursor.arrow.set()
    }

    func cancel() {
        finish(screen: nil, rect: nil)
    }
}

// MARK: - Ventana

private protocol SelectionOverlayDelegate: AnyObject {
    func overlay(_ window: SelectionOverlayWindow, didSelect rect: CGRect)
    func overlayDidCancel(_ window: SelectionOverlayWindow)
}

extension RegionSelectionController: SelectionOverlayDelegate {
    fileprivate func overlay(_ window: SelectionOverlayWindow, didSelect rect: CGRect) {
        finish(screen: window.targetScreen, rect: rect)
    }

    fileprivate func overlayDidCancel(_ window: SelectionOverlayWindow) {
        finish(screen: nil, rect: nil)
    }
}

private final class SelectionOverlayWindow: NSWindow {
    let targetScreen: NSScreen
    weak var selectionDelegate: SelectionOverlayDelegate?

    init(screen: NSScreen) {
        self.targetScreen = screen
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        setFrame(screen.frame, display: true)

        let view = SelectionOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.overlayWindow = self
        contentView = view
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    fileprivate func report(rect: CGRect) {
        // De coordenadas de la vista a coordenadas globales de pantalla.
        let global = CGRect(x: targetScreen.frame.minX + rect.minX,
                            y: targetScreen.frame.minY + rect.minY,
                            width: rect.width,
                            height: rect.height)
        selectionDelegate?.overlay(self, didSelect: global)
    }

    fileprivate func reportCancel() {
        selectionDelegate?.overlayDidCancel(self)
    }
}

// MARK: - Vista

private final class SelectionOverlayView: NSView {
    weak var overlayWindow: SelectionOverlayWindow?

    private var anchor: CGPoint?
    private var current: CGPoint?

    private var selectionRect: CGRect? {
        guard let anchor, let current else { return nil }
        return CGRect(x: min(anchor.x, current.x),
                      y: min(anchor.y, current.y),
                      width: abs(current.x - anchor.x),
                      height: abs(current.y - anchor.y))
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        NSCursor.crosshair.set()
    }

    // MARK: Eventos

    override func mouseDown(with event: NSEvent) {
        // Al empezar a seleccionar en otro monitor, esa ventana pasa a ser la principal
        // para que Esc siga cancelando.
        window?.makeKey()
        anchor = convert(event.locationInWindow, from: nil)
        current = anchor
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        guard let rect = selectionRect, rect.width >= 2, rect.height >= 2 else {
            // Un clic sin arrastre cancela, igual que en las utilidades del sistema.
            overlayWindow?.reportCancel()
            return
        }
        overlayWindow?.report(rect: rect)
    }

    override func rightMouseDown(with event: NSEvent) {
        overlayWindow?.reportCancel()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            overlayWindow?.reportCancel()
        } else {
            super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        overlayWindow?.reportCancel()
    }

    // MARK: Dibujo

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Velo oscuro sobre todo lo que no está seleccionado.
        context.setFillColor(NSColor.black.withAlphaComponent(0.35).cgColor)
        context.fill(bounds)

        if let rect = selectionRect, rect.width > 0, rect.height > 0 {
            context.setBlendMode(.clear)
            context.fill(rect)
            context.setBlendMode(.normal)

            context.setStrokeColor(NSColor.white.cgColor)
            context.setLineWidth(1)
            context.stroke(rect.insetBy(dx: 0.5, dy: 0.5))

            drawDimensions(for: rect, in: context)
        }
        // Antes de arrastrar no se dibuja nada más: la referencia es el propio cursor de cruz
        // del sistema. Unas guías cruzando toda la pantalla resultaban invasivas.
    }

    private func drawDimensions(for rect: CGRect, in context: CGContext) {
        let scale = overlayWindow?.targetScreen.backingScaleFactor ?? 1
        let pixels = "\(Int((rect.width * scale).rounded())) × \(Int((rect.height * scale).rounded())) px"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let text = NSAttributedString(string: pixels, attributes: attributes)
        let size = text.size()
        let padding: CGFloat = 6
        var origin = CGPoint(x: rect.minX, y: rect.minY - size.height - padding * 2 - 4)
        if origin.y < bounds.minY + 4 {
            origin.y = rect.maxY + 4
        }
        let box = CGRect(x: origin.x, y: origin.y, width: size.width + padding * 2, height: size.height + padding)

        context.setFillColor(NSColor.black.withAlphaComponent(0.75).cgColor)
        let path = CGPath(roundedRect: box, cornerWidth: 5, cornerHeight: 5, transform: nil)
        context.addPath(path)
        context.fillPath()

        text.draw(at: CGPoint(x: box.minX + padding, y: box.minY + padding / 2))
    }
}
