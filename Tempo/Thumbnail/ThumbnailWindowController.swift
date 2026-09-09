import AppKit

protocol ThumbnailWindowDelegate: AnyObject {
    /// Un clic sobre la miniatura: abrir el editor.
    func thumbnailRequestedOpen(_ controller: ThumbnailWindowController)
    /// El botón de cerrar: descartar la captura.
    func thumbnailRequestedDismiss(_ controller: ThumbnailWindowController)
    /// Se va a iniciar un arrastre: hay que materializar en disco las imágenes finales.
    ///
    /// Devuelve una URL por captura del mazo, en orden, porque al arrastrar se entregan todas
    /// y no sólo la que está encima.
    func thumbnailFileURLsForDragging(_ controller: ThumbnailWindowController) -> [URL]
    /// El arrastre terminó copiando la imagen en otra aplicación.
    func thumbnailDidFinishDrag(_ controller: ThumbnailWindowController, accepted: Bool)
    /// Copiar la imagen sin pasar por el editor.
    func thumbnailRequestedCopy(_ controller: ThumbnailWindowController)
    /// Guardar la imagen sin pasar por el editor.
    func thumbnailRequestedSave(_ controller: ThumbnailWindowController)
}

/// Panel flotante compacto que aparece tras cada captura.
///
/// Es un `NSPanel` no activador: se mantiene por encima del resto de ventanas y en todos los
/// escritorios sin robar el foco, de modo que el usuario puede seguir trabajando y arrastrar
/// la imagen a un navegador o a una app de escritorio cuando le convenga.
final class ThumbnailWindowController: NSWindowController {

    weak var delegate: ThumbnailWindowDelegate?
    let sessionID: UUID

    private let thumbnailView: ThumbnailView

    /// Tamaño máximo del panel; la miniatura conserva la proporción de la captura.
    private static let maxSize = CGSize(width: 208, height: 168)
    private static let minSide: CGFloat = 72

    init(sessionID: UUID, image: NSImage) {
        self.sessionID = sessionID
        let size = ThumbnailWindowController.fittedSize(for: image.size)
        thumbnailView = ThumbnailView(frame: NSRect(origin: .zero, size: size))
        thumbnailView.image = image

        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isMovableByWindowBackground = false
        panel.contentView = thumbnailView

        super.init(window: panel)
        thumbnailView.controller = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) no está soportado")
    }

    // MARK: - Presentación

    /// Coloca el panel en la esquina inferior derecha de la pantalla, desplazado hacia arriba
    /// tantas posiciones como capturas haya ya visibles.
    func position(on screen: NSScreen, stackIndex: Int) {
        guard let window else { return }
        let margin: CGFloat = 20
        let spacing: CGFloat = 12
        let size = window.frame.size
        let visible = screen.visibleFrame

        let x = visible.maxX - size.width - margin
        let y = visible.minY + margin + CGFloat(stackIndex) * (size.height + spacing)
        window.setFrameOrigin(NSPoint(x: x, y: min(y, visible.maxY - size.height - margin)))
    }

    func show() {
        window?.orderFrontRegardless()
        thumbnailView.playAppearAnimation()
    }

    func hide() {
        window?.orderOut(nil)
    }

    func close(animated: Bool) {
        guard animated, let window else {
            window?.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            window.animator().alphaValue = 0
        } completionHandler: {
            window.orderOut(nil)
            window.alphaValue = 1
        }
    }

    /// Cuántas capturas hay en total. Cuando son varias, la miniatura se dibuja como un mazo:
    /// las de detrás asoman por la esquina y un contador indica el total.
    func updateStack(total: Int) {
        thumbnailView.stackCount = total
    }

    /// Refresca la imagen mostrada, por ejemplo tras anotar o recortar en el editor.
    ///
    /// El panel se redimensiona si la captura ha cambiado de proporción: recortar puede pasar
    /// de apaisado a cuadrado, y mantener el tamaño anterior deformaría la miniatura.
    func update(image: NSImage) {
        thumbnailView.image = image
        thumbnailView.needsDisplay = true

        let fitted = ThumbnailWindowController.fittedSize(for: image.size)
        guard let window, window.frame.size != fitted else { return }
        // Se ancla la esquina inferior derecha, que es por donde se apilan las miniaturas.
        let origin = NSPoint(x: window.frame.maxX - fitted.width, y: window.frame.minY)
        window.setFrame(NSRect(origin: origin, size: fitted), display: true)
        thumbnailView.frame = NSRect(origin: .zero, size: fitted)
    }

    // MARK: - Puente con la vista

    fileprivate func requestOpen() { delegate?.thumbnailRequestedOpen(self) }
    fileprivate func requestCopy() { delegate?.thumbnailRequestedCopy(self) }
    fileprivate func requestSave() { delegate?.thumbnailRequestedSave(self) }
    fileprivate func requestDismiss() { delegate?.thumbnailRequestedDismiss(self) }
    fileprivate func fileURLsForDragging() -> [URL] { delegate?.thumbnailFileURLsForDragging(self) ?? [] }
    fileprivate func dragFinished(accepted: Bool) { delegate?.thumbnailDidFinishDrag(self, accepted: accepted) }

    /// Tamaño del panel para una captura dada. La proporción de la imagen se respeta siempre:
    /// las capturas grandes se reducen para caber y las diminutas se amplían lo justo para
    /// seguir siendo visibles, nunca más allá del tamaño máximo.
    static func fittedSize(for imageSize: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else { return maxSize }

        let fit = min(maxSize.width / imageSize.width, maxSize.height / imageSize.height)
        var scale = min(fit, 1)

        let shortestSide = min(imageSize.width, imageSize.height) * scale
        if shortestSide < minSide {
            scale = min(fit, minSide / min(imageSize.width, imageSize.height))
        }

        return CGSize(width: max(1, (imageSize.width * scale).rounded()),
                      height: max(1, (imageSize.height * scale).rounded()))
    }
}

// MARK: - Vista

private final class ThumbnailView: NSView, NSDraggingSource {

    weak var controller: ThumbnailWindowController?
    var image: NSImage?

    /// Número total de capturas vivas. Con más de una, la miniatura se dibuja como un mazo.
    var stackCount = 1 {
        didSet { needsDisplay = true }
    }

    private var isHovered = false
    private var isDragging = false
    private var mouseDownLocation: CGPoint?
    private var trackingArea: NSTrackingArea?

    private let cornerRadius: CGFloat = 10
    private let closeButtonRadius: CGFloat = 9
    private let closeButtonInset: CGFloat = 7

    override var isFlipped: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Seguimiento del ratón

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    // MARK: Clic y arrastre

    private var closeButtonRect: CGRect {
        CGRect(x: imageRect.minX + closeButtonInset,
               y: imageRect.maxY - closeButtonInset - closeButtonRadius * 2,
               width: closeButtonRadius * 2,
               height: closeButtonRadius * 2)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if isHovered, closeButtonRect.insetBy(dx: -3, dy: -3).contains(point) {
            controller?.requestDismiss()
            return
        }
        mouseDownLocation = point
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownLocation, !isDragging else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - start.x, point.y - start.y) > 3 else { return }
        isDragging = true
        beginImageDrag(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            mouseDownLocation = nil
            isDragging = false
        }
        guard !isDragging, mouseDownLocation != nil else { return }
        controller?.requestOpen()
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        menu.addItem(withTitle: "Abrir editor", action: #selector(menuOpen), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Copiar", action: #selector(menuCopy), keyEquivalent: "")
        menu.addItem(withTitle: "Guardar como PNG…", action: #selector(menuSave), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Descartar", action: #selector(menuDismiss), keyEquivalent: "")
        for item in menu.items where item.action != nil {
            item.target = self
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func menuOpen() { controller?.requestOpen() }
    @objc private func menuCopy() { controller?.requestCopy() }
    @objc private func menuSave() { controller?.requestSave() }
    @objc private func menuDismiss() { controller?.requestDismiss() }

    private func beginImageDrag(with event: NSEvent) {
        let urls = controller?.fileURLsForDragging() ?? []
        guard !urls.isEmpty else {
            isDragging = false
            return
        }

        // Un elemento por captura: al soltar el mazo se entregan todas, no sólo la de encima.
        // Los de detrás se colocan escalonados, como se ven en la miniatura.
        let items: [NSDraggingItem] = urls.enumerated().map { index, url in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let offset = CGFloat(min(index, maximumSheets)) * sheetOffset
            let frame = imageRect.offsetBy(dx: offset, dy: -offset)
            // Sólo la de delante lleva vista previa; las demás arrastran su icono de archivo.
            item.setDraggingFrame(frame, contents: index == 0 ? image : nil)
            return item
        }

        let session = beginDraggingSession(with: items, event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = urls.count > 1 ? .stack : .none
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        // `.copy` hacia otras aplicaciones: la captura original nunca se mueve ni se borra.
        return .copy
    }

    func draggingSession(_ session: NSDraggingSession,
                         endedAt screenPoint: NSPoint,
                         operation: NSDragOperation) {
        isDragging = false
        mouseDownLocation = nil
        controller?.dragFinished(accepted: operation != [])
    }

    // MARK: Dibujo

    /// Desplazamiento de cada hoja del mazo respecto a la de delante.
    private let sheetOffset: CGFloat = 5
    /// Cuántas hojas de detrás se llegan a dibujar, por muchas capturas que haya.
    private let maximumSheets = 3

    /// Hojas visibles por detrás de la de delante.
    private var visibleSheets: Int {
        min(max(stackCount - 1, 0), maximumSheets)
    }

    /// Rectángulo de la hoja de delante, que deja hueco a las de detrás.
    private var imageRect: CGRect {
        let room = CGFloat(visibleSheets) * sheetOffset
        return CGRect(x: bounds.minX, y: bounds.minY + room,
                      width: bounds.width - room, height: bounds.height - room)
    }

    func playAppearAnimation() {
        alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            animator().alphaValue = 1
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Hojas de detrás, de la más lejana a la más cercana: sólo se ve su esquina asomando,
        // que es lo que da a entender que hay más capturas debajo.
        for sheet in stride(from: visibleSheets, to: 0, by: -1) {
            let inset = CGFloat(sheet) * sheetOffset
            // Cada hoja se desplaza a la derecha y hacia abajo respecto a la de delante.
            let sheetRect = imageRect.offsetBy(dx: inset, dy: -inset)
            let path = CGPath(roundedRect: sheetRect.insetBy(dx: 0.5, dy: 0.5),
                              cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
            context.addPath(path)
            // Cuanto más atrás, más apagada.
            let tone = 0.42 - Double(sheet) * 0.06
            context.setFillColor(NSColor(white: tone, alpha: 1).cgColor)
            context.fillPath()
            context.addPath(path)
            context.setStrokeColor(NSColor.white.withAlphaComponent(0.30).cgColor)
            context.setLineWidth(1)
            context.strokePath()
        }

        let front = imageRect
        let path = CGPath(roundedRect: front.insetBy(dx: 0.5, dy: 0.5),
                          cornerWidth: cornerRadius,
                          cornerHeight: cornerRadius,
                          transform: nil)

        context.saveGState()
        context.addPath(path)
        context.clip()

        // Fondo por si la imagen tiene transparencia.
        context.setFillColor(NSColor.windowBackgroundColor.cgColor)
        context.fill(front)

        if let image {
            image.draw(in: front, from: .zero, operation: .sourceOver, fraction: 1,
                       respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])
        }
        context.restoreGState()

        // Borde sutil que separa la miniatura del contenido de detrás.
        context.addPath(path)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.55).cgColor)
        context.setLineWidth(1)
        context.strokePath()

        if stackCount > 1 {
            drawCounter(in: context, frontRect: front)
        }

        if isHovered {
            drawCloseButton(in: context)
        }
    }

    /// Contador con el total de capturas, en la esquina inferior derecha del mazo.
    private func drawCounter(in context: CGContext, frontRect: CGRect) {
        let text = NSAttributedString(string: "\(stackCount)", attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .bold),
            .foregroundColor: NSColor.white
        ])
        let size = text.size()
        let diameter = max(size.width + 12, 20)
        let badge = CGRect(x: frontRect.maxX - diameter - 6,
                           y: frontRect.minY + 6,
                           width: diameter,
                           height: 20)

        context.setFillColor(NSColor.controlAccentColor.cgColor)
        context.addPath(CGPath(roundedRect: badge, cornerWidth: 10, cornerHeight: 10, transform: nil))
        context.fillPath()

        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        text.draw(at: CGPoint(x: badge.midX - size.width / 2, y: badge.midY - size.height / 2))
        NSGraphicsContext.current = previous
    }

    private func drawCloseButton(in context: CGContext) {
        let rect = closeButtonRect
        context.setFillColor(NSColor.black.withAlphaComponent(0.62).cgColor)
        context.fillEllipse(in: rect)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.85).cgColor)
        context.setLineWidth(1.6)
        context.setLineCap(.round)
        let inset = rect.insetBy(dx: rect.width * 0.3, dy: rect.height * 0.3)
        context.beginPath()
        context.move(to: CGPoint(x: inset.minX, y: inset.minY))
        context.addLine(to: CGPoint(x: inset.maxX, y: inset.maxY))
        context.move(to: CGPoint(x: inset.minX, y: inset.maxY))
        context.addLine(to: CGPoint(x: inset.maxX, y: inset.minY))
        context.strokePath()
    }
}
