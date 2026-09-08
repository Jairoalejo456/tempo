import AppKit
import Combine

/// Lienzo del editor: dibuja la captura con sus anotaciones y traduce los gestos del ratón
/// a nuevas anotaciones.
///
/// El dibujo se delega íntegramente en `AnnotationRenderer`, el mismo que usa el exportador,
/// aplicando una transformación de escala: lo que se ve aquí es exactamente lo que se copia.
final class CanvasView: NSView {

    let document: EditorDocument
    private var cancellables: Set<AnyCancellable> = []

    /// Gesto en curso.
    private var gestureAnchor: CGPoint?
    private var isDrawing = false

    /// Desplazamiento en curso con la herramienta puntero.
    private var isPanning = false
    private var panAnchor: CGPoint?
    private var panOffsetAtDragStart: CGPoint = .zero

    /// Manipulación en curso de una anotación ya existente.
    private enum Manipulation {
        case moving(id: UUID, grabPoint: CGPoint, original: Annotation)
        case resizing(id: UUID, handle: AnnotationHandle)
        case rotating(id: UUID)
    }
    private var manipulation: Manipulation?

    /// Radio, en puntos de pantalla, de los tiradores de la selección.
    private let handleRadius: CGFloat = 4.5

    /// Editor de texto en línea, cuando la herramienta de texto está activa.
    private var textEditor: InlineTextEditor?
    private var textEditorOrigin: CGPoint?
    /// Si se está reeditando un texto ya existente en lugar de crear uno nuevo.
    private var textEditorAnnotationID: UUID?


    init(document: EditorDocument) {
        self.document = document
        super.init(frame: .zero)
        wantsLayer = true

        // Cualquier cambio en el modelo repinta el lienzo.
        document.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.needsDisplay = true }
            .store(in: &cancellables)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) no está soportado")
    }

    // MARK: - Geometría

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private let padding: CGFloat = 16
    /// Ampliación máxima respecto al tamaño real de la captura.
    private let maximumScale: CGFloat = 8

    /// Desplazamiento aplicado al arrastrar con el puntero.
    private var panOffset: CGPoint = .zero

    /// Escala a la que la captura cabe entera en la ventana (nunca amplía por sí sola).
    var fitScale: CGFloat {
        let available = bounds.insetBy(dx: padding, dy: padding).size
        let image = document.capture.logicalSize
        guard image.width > 0, image.height > 0, available.width > 0, available.height > 0 else { return 1 }
        return min(available.width / image.width, available.height / image.height, 1)
    }

    /// Escala realmente aplicada: el ajuste a ventana multiplicado por el zoom del usuario.
    var displayScale: CGFloat {
        fitScale * document.zoomFactor
    }

    /// Rectángulo, en coordenadas de la vista, donde se dibuja la captura.
    var imageFrame: CGRect {
        let scale = displayScale
        let size = CGSize(width: document.capture.logicalSize.width * scale,
                          height: document.capture.logicalSize.height * scale)
        return CGRect(x: ((bounds.width - size.width) / 2 + panOffset.x).rounded(),
                      y: ((bounds.height - size.height) / 2 + panOffset.y).rounded(),
                      width: size.width,
                      height: size.height)
    }

    // MARK: - Zoom

    private var minimumZoomFactor: CGFloat { 0.2 }
    private var maximumZoomFactor: CGFloat { max(1, maximumScale / max(fitScale, 0.0001)) }

    /// Ajusta el zoom manteniendo fijo el punto de la imagen que está bajo el cursor.
    func setZoom(_ factor: CGFloat, anchorInView anchor: CGPoint?) {
        let clamped = min(max(factor, minimumZoomFactor), maximumZoomFactor)
        guard abs(clamped - document.zoomFactor) > 0.0001 else { return }

        let anchorPoint = anchor ?? CGPoint(x: bounds.midX, y: bounds.midY)
        let imageAnchor = imagePoint(from: anchorPoint)

        document.zoomFactor = clamped

        let moved = viewPoint(from: imageAnchor)
        panOffset.x += anchorPoint.x - moved.x
        panOffset.y += anchorPoint.y - moved.y

        clampPan()
        refreshViewport()
    }

    func zoomIn() { setZoom(document.zoomFactor * 1.25, anchorInView: nil) }
    func zoomOut() { setZoom(document.zoomFactor / 1.25, anchorInView: nil) }

    /// Vuelve a mostrar la captura completa, centrada.
    func zoomToFit() {
        document.zoomFactor = 1
        panOffset = .zero
        refreshViewport()
    }

    /// Muestra la captura a su tamaño real (100 %).
    func zoomToActualSize() {
        setZoom(1 / max(fitScale, 0.0001), anchorInView: nil)
    }

    /// Evita que la captura se pierda fuera de la ventana al desplazarla.
    private func clampPan() {
        let size = CGSize(width: document.capture.logicalSize.width * displayScale,
                          height: document.capture.logicalSize.height * displayScale)

        if size.width <= bounds.width {
            panOffset.x = 0
        } else {
            let limit = (size.width - bounds.width) / 2 + padding
            panOffset.x = min(max(panOffset.x, -limit), limit)
        }

        if size.height <= bounds.height {
            panOffset.y = 0
        } else {
            let limit = (size.height - bounds.height) / 2 + padding
            panOffset.y = min(max(panOffset.y, -limit), limit)
        }
    }

    private func refreshViewport() {
        document.fitScale = fitScale
        needsDisplay = true
        discardCursorRects()
        window?.invalidateCursorRects(for: self)
    }

    func imagePoint(from viewPoint: CGPoint) -> CGPoint {
        let frame = imageFrame
        let scale = displayScale
        guard scale > 0 else { return .zero }
        return CGPoint(x: (viewPoint.x - frame.minX) / scale,
                       y: (viewPoint.y - frame.minY) / scale)
    }

    func viewPoint(from imagePoint: CGPoint) -> CGPoint {
        let frame = imageFrame
        let scale = displayScale
        return CGPoint(x: frame.minX + imagePoint.x * scale,
                       y: frame.minY + imagePoint.y * scale)
    }

    /// Mantiene el punto dentro de los límites de la captura.
    private func clamped(_ point: CGPoint) -> CGPoint {
        let size = document.capture.logicalSize
        return CGPoint(x: min(max(point.x, 0), size.width),
                       y: min(max(point.y, 0), size.height))
    }

    // MARK: - Dibujo

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let frame = imageFrame
        let scale = displayScale

        // Sombra suave bajo la captura para separarla del fondo de la ventana.
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -2), blur: 12,
                          color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.28))
        context.setFillColor(NSColor.black.withAlphaComponent(0.001).cgColor)
        context.fill(frame)
        context.restoreGState()

        context.saveGState()
        context.clip(to: frame)
        context.translateBy(x: frame.minX, y: frame.minY)
        context.scaleBy(x: scale, y: scale)
        AnnotationRenderer.drawBase(document.capture, in: context)
        AnnotationRenderer.draw(document.renderableAnnotations, capture: document.capture, in: context)
        context.restoreGState()

        // La selección se dibuja fuera de la escala de la imagen para que su grosor y sus
        // tiradores midan siempre lo mismo en pantalla, sea cual sea el zoom.
        if let selected = document.selectedAnnotation, document.draft == nil {
            drawSelection(for: selected, in: context)
        }
    }

    /// Contorno y tiradores de la anotación seleccionada.
    private func drawSelection(for annotation: Annotation, in context: CGContext) {
        let bounds = annotation.localBounds
        let corners = [
            CGPoint(x: bounds.minX, y: bounds.minY),
            CGPoint(x: bounds.maxX, y: bounds.minY),
            CGPoint(x: bounds.maxX, y: bounds.maxY),
            CGPoint(x: bounds.minX, y: bounds.maxY)
        ].map { viewPoint(from: annotation.toImage($0)) }

        context.saveGState()
        context.setStrokeColor(NSColor.controlAccentColor.cgColor)
        context.setLineWidth(1)
        context.setLineDash(phase: 0, lengths: [4, 3])
        context.beginPath()
        context.move(to: corners[0])
        for corner in corners.dropFirst() { context.addLine(to: corner) }
        context.closePath()
        context.strokePath()
        context.setLineDash(phase: 0, lengths: [])

        let handles = annotation.handlePositions()

        // Línea que une el tirador de giro con el borde superior.
        if let rotateHandle = handles[.rotate] {
            let top = viewPoint(from: annotation.toImage(CGPoint(x: bounds.midX, y: bounds.maxY)))
            context.beginPath()
            context.move(to: top)
            context.addLine(to: viewPoint(from: rotateHandle))
            context.strokePath()
        }

        for (handle, position) in handles {
            let point = viewPoint(from: position)
            let rect = CGRect(x: point.x - handleRadius, y: point.y - handleRadius,
                              width: handleRadius * 2, height: handleRadius * 2)
            context.setFillColor(NSColor.white.cgColor)
            context.setStrokeColor(NSColor.controlAccentColor.cgColor)
            context.setLineWidth(1.5)
            if handle == .rotate {
                context.fillEllipse(in: rect)
                context.strokeEllipse(in: rect)
            } else {
                context.fill(rect)
                context.stroke(rect)
            }
        }
        context.restoreGState()
    }

    override func resetCursorRects() {
        switch document.tool {
        case .navigate:
            // Con el puntero, la mano cerrada sólo mientras se arrastra el fondo.
            addCursorRect(bounds, cursor: isPanning ? .closedHand : .arrow)
        case .annotate:
            addCursorRect(imageFrame, cursor: .crosshair)
        }
    }

    private func refreshCursor() {
        discardCursorRects()
        window?.invalidateCursorRects(for: self)
    }

    override func layout() {
        super.layout()
        clampPan()
        refreshViewport()
    }

    // MARK: - Gestos

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)

        // Si había un texto en edición, un clic fuera lo confirma.
        if textEditor != nil {
            commitTextEditor()
            return
        }

        // Puntero: selecciona, mueve, redimensiona y gira lo ya dibujado; sobre zona vacía,
        // desplaza la captura.
        if document.tool == .navigate {
            handlePointerMouseDown(event)
            return
        }

        // Con una herramienta de dibujo, empezar un trazo nuevo deselecciona lo anterior.
        document.select(nil)

        guard let tool = document.tool.annotationTool else { return }

        let point = clamped(imagePoint(from: convert(event.locationInWindow, from: nil)))
        guard imageFrame.insetBy(dx: -2, dy: -2).contains(convert(event.locationInWindow, from: nil)) else { return }

        switch tool {
        case .counter:
            let annotation = Annotation(shape: .counter(center: point, number: document.nextCounterNumber),
                                        style: document.currentStyle)
            document.place(annotation, keepingTool: keepsTool(event))
            refreshCursor()
        case .text:
            beginTextEditing(at: point)
        case .arrow, .rectangle, .ellipse, .blur, .pencil:
            gestureAnchor = point
            isDrawing = true
            document.draft = makeDraft(from: point, to: point, points: [point])
        }
    }

    /// Reparte el clic del puntero entre tirador, anotación y fondo.
    private func handlePointerMouseDown(_ event: NSEvent) {
        let viewLocation = convert(event.locationInWindow, from: nil)
        let imageLocation = imagePoint(from: viewLocation)
        let tolerance = handleTolerance

        // 1. Un tirador de la selección actual tiene prioridad sobre todo lo demás.
        if let selected = document.selectedAnnotation,
           let handle = selected.handle(at: imageLocation, tolerance: tolerance) {
            document.beginInteractiveChange()
            manipulation = handle == .rotate
                ? .rotating(id: selected.id)
                : .resizing(id: selected.id, handle: handle)
            return
        }

        // 2. ¿Hay una anotación bajo el cursor?
        if let hit = document.annotation(at: imageLocation, tolerance: tolerance) {
            document.select(hit.id)

            if event.clickCount == 2 {
                beginEditing(hit)
                return
            }

            document.beginInteractiveChange()
            manipulation = .moving(id: hit.id, grabPoint: imageLocation, original: hit)
            return
        }

        // 3. Fondo: se deselecciona y se desplaza la captura.
        document.select(nil)
        if event.clickCount == 2 {
            zoomToFit()
            return
        }
        isPanning = true
        panAnchor = viewLocation
        panOffsetAtDragStart = panOffset
        refreshCursor()
    }

    /// Tolerancia de acierto en coordenadas de imagen: constante en pantalla, sea cual sea el zoom.
    private var handleTolerance: CGFloat {
        max(handleRadius + 3, 9) / max(displayScale, 0.0001)
    }

    override func mouseDragged(with event: NSEvent) {
        if let manipulation {
            applyManipulation(manipulation, with: event)
            return
        }

        if isPanning, let anchor = panAnchor {
            let current = convert(event.locationInWindow, from: nil)
            panOffset = CGPoint(x: panOffsetAtDragStart.x + current.x - anchor.x,
                                y: panOffsetAtDragStart.y + current.y - anchor.y)
            clampPan()
            needsDisplay = true
            return
        }

        guard isDrawing, let anchor = gestureAnchor, let tool = document.tool.annotationTool else { return }
        var point = clamped(imagePoint(from: convert(event.locationInWindow, from: nil)))

        if event.modifierFlags.contains(.shift) {
            point = constrained(point, from: anchor, tool: tool)
        }

        if tool == .pencil, case let .pencil(existing)? = document.draft?.shape {
            var points = existing
            // Se descartan micro‑movimientos para que el trazo sea ligero y suave.
            if let last = points.last, hypot(point.x - last.x, point.y - last.y) < 1.2 { return }
            points.append(point)
            document.draft = Annotation(id: document.draft?.id ?? UUID(),
                                        shape: .pencil(points: points),
                                        style: document.currentStyle)
        } else {
            document.draft = makeDraft(from: anchor, to: point, points: [anchor, point])
        }
        needsDisplay = true
    }

    /// Aplica el arrastre en curso sobre la anotación seleccionada.
    private func applyManipulation(_ manipulation: Manipulation, with event: NSEvent) {
        let imageLocation = imagePoint(from: convert(event.locationInWindow, from: nil))
        let shiftPressed = event.modifierFlags.contains(.shift)

        switch manipulation {
        case let .moving(id, grabPoint, original):
            guard document.annotations.contains(where: { $0.id == id }) else { return }
            let delta = CGSize(width: imageLocation.x - grabPoint.x,
                               height: imageLocation.y - grabPoint.y)
            document.updateLive(original.moved(by: delta))
        case let .resizing(id, handle):
            guard let annotation = document.annotations.first(where: { $0.id == id }) else { return }
            document.updateLive(annotation.resized(handle: handle, to: imageLocation, keepingAspect: shiftPressed))
        case let .rotating(id):
            guard let annotation = document.annotations.first(where: { $0.id == id }) else { return }
            document.updateLive(annotation.rotated(towards: imageLocation, snapping: shiftPressed))
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if manipulation != nil {
            manipulation = nil
            document.endInteractiveChange()
            refreshCursor()
            return
        }

        if isPanning {
            isPanning = false
            panAnchor = nil
            refreshCursor()
            return
        }

        defer {
            isDrawing = false
            gestureAnchor = nil
        }
        guard isDrawing, let draft = document.draft else { return }
        document.draft = nil
        document.place(draft, keepingTool: keepsTool(event))
        refreshCursor()
        needsDisplay = true
    }

    /// Manteniendo ⌥ al soltar, la herramienta sigue activa en lugar de volver al puntero.
    private func keepsTool(_ event: NSEvent?) -> Bool {
        event?.modifierFlags.contains(.option) ?? false
    }

    private func makeDraft(from: CGPoint, to: CGPoint, points: [CGPoint]) -> Annotation {
        let rect = CGRect(x: min(from.x, to.x), y: min(from.y, to.y),
                          width: abs(to.x - from.x), height: abs(to.y - from.y))
        let shape: AnnotationShape
        switch document.tool.annotationTool ?? .arrow {
        case .arrow: shape = .arrow(from: from, to: to)
        case .rectangle: shape = .rectangle(rect)
        case .ellipse: shape = .ellipse(rect)
        case .blur: shape = .blur(rect)
        case .pencil: shape = .pencil(points: points)
        case .text: shape = .text(origin: from, string: "")
        case .counter: shape = .counter(center: from, number: document.nextCounterNumber)
        }
        return Annotation(id: document.draft?.id ?? UUID(), shape: shape, style: document.currentStyle)
    }

    // MARK: - Rueda y gestos de zoom

    /// La rueda del ratón hace zoom, acercando o alejando alrededor del cursor.
    ///
    /// Con el trackpad se distingue: dos dedos desplazan la captura (que es el gesto que se
    /// espera en macOS) y el pellizco hace zoom.
    override func scrollWheel(with event: NSEvent) {
        let anchor = convert(event.locationInWindow, from: nil)

        if event.hasPreciseScrollingDeltas {
            panOffset.x += event.scrollingDeltaX
            panOffset.y += event.scrollingDeltaY
            clampPan()
            needsDisplay = true
            return
        }

        guard event.scrollingDeltaY != 0 else { return }
        let step: CGFloat = event.scrollingDeltaY > 0 ? 1.12 : 1 / 1.12
        setZoom(document.zoomFactor * step, anchorInView: anchor)
    }

    override func magnify(with event: NSEvent) {
        let anchor = convert(event.locationInWindow, from: nil)
        setZoom(document.zoomFactor * (1 + event.magnification), anchorInView: anchor)
    }

    /// Con la tecla Mayúsculas: cuadrados, círculos y flechas en ángulos de 45°.
    private func constrained(_ point: CGPoint, from anchor: CGPoint, tool: AnnotationTool) -> CGPoint {
        switch tool {
        case .rectangle, .ellipse, .blur:
            let side = max(abs(point.x - anchor.x), abs(point.y - anchor.y))
            return CGPoint(x: anchor.x + side * (point.x < anchor.x ? -1 : 1),
                           y: anchor.y + side * (point.y < anchor.y ? -1 : 1))
        case .arrow:
            let dx = point.x - anchor.x
            let dy = point.y - anchor.y
            let angle = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
            let length = hypot(dx, dy)
            return CGPoint(x: anchor.x + cos(angle) * length, y: anchor.y + sin(angle) * length)
        default:
            return point
        }
    }

    // MARK: - Edición del contenido (doble clic)

    /// Doble clic sobre una anotación de texto entra a reescribirla. Un contador no necesita
    /// nada: basta con tenerlo seleccionado y teclear el número.
    private func beginEditing(_ annotation: Annotation) {
        guard annotation.textContent != nil else { return }
        beginTextEditing(editing: annotation)
    }

    // MARK: - Texto en línea

    var isEditingText: Bool { textEditor != nil }

    /// Reedita un texto ya existente.
    private func beginTextEditing(editing annotation: Annotation) {
        guard case let .text(origin, string) = annotation.shape else { return }
        commitTextEditor()
        beginTextEditing(at: origin, style: annotation.style, existing: string, annotationID: annotation.id)
    }

    private func beginTextEditing(at point: CGPoint,
                                  style overrideStyle: AnnotationStyle? = nil,
                                  existing: String = "",
                                  annotationID: UUID? = nil) {
        commitTextEditor()

        let style = overrideStyle ?? document.currentStyle
        let scale = displayScale
        // El campo de edición usa la misma escala que el lienzo, de modo que el texto que se
        // escribe tiene el tamaño exacto con el que se va a dibujar.
        let font = NSFont.systemFont(ofSize: style.fontSize * scale, weight: .semibold)
        let lineHeight = ceil(font.ascender - font.descender + font.leading)

        let origin = viewPoint(from: point)
        let editor = InlineTextEditor(frame: CGRect(x: origin.x, y: origin.y,
                                                    width: max(120, bounds.maxX - origin.x - padding),
                                                    height: lineHeight))
        editor.configure(font: font, color: NSColor(cgColor: style.color.cgColor) ?? .systemRed)
        editor.onCommit = { [weak self] in self?.commitTextEditor() }
        editor.onCancel = { [weak self] in self?.cancelTextEditor() }

        editor.string = existing
        addSubview(editor)
        window?.makeFirstResponder(editor)
        if !existing.isEmpty {
            editor.setSelectedRange(NSRange(location: 0, length: (existing as NSString).length))
        }

        textEditor = editor
        textEditorOrigin = point
        textEditorAnnotationID = annotationID
    }

    /// Confirma el texto en edición convirtiéndolo en anotación.
    @discardableResult
    func commitTextEditor() -> Bool {
        guard let editor = textEditor, let origin = textEditorOrigin else { return false }
        let string = editor.string
        let annotationID = textEditorAnnotationID
        textEditor = nil
        textEditorOrigin = nil
        textEditorAnnotationID = nil
        editor.removeFromSuperview()
        window?.makeFirstResponder(self)

        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)

        if let annotationID, let existing = document.annotations.first(where: { $0.id == annotationID }) {
            // Reedición: un texto vaciado equivale a borrar la anotación.
            if trimmed.isEmpty {
                document.select(annotationID)
                document.deleteSelected()
            } else {
                document.replace(existing.withText(string))
            }
            needsDisplay = true
            return true
        }

        guard !trimmed.isEmpty else { return false }
        document.place(Annotation(shape: .text(origin: origin, string: string), style: document.currentStyle))
        refreshCursor()
        needsDisplay = true
        return true
    }

    func cancelTextEditor() {
        guard let editor = textEditor else { return }
        textEditor = nil
        textEditorOrigin = nil
        textEditorAnnotationID = nil
        editor.removeFromSuperview()
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    // MARK: - Teclado

    override func keyDown(with event: NSEvent) {
        // Retroceso: borra lo seleccionado, o la última anotación si no hay nada elegido.
        if event.keyCode == 51 || event.keyCode == 117 { // Delete / Fn+Delete
            if document.selectedAnnotation != nil {
                document.deleteSelected()
            } else {
                document.removeLast()
            }
            return
        }

        // Las flechas mueven la anotación seleccionada; con Mayúsculas, a pasos mayores.
        if let selected = document.selectedAnnotation, let delta = arrowDelta(for: event) {
            document.beginInteractiveChange()
            document.updateLive(selected.moved(by: delta))
            document.endInteractiveChange()
            needsDisplay = true
            return
        }

        super.keyDown(with: event)
    }

    private func arrowDelta(for event: NSEvent) -> CGSize? {
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
        switch event.keyCode {
        case 123: return CGSize(width: -step, height: 0) // ←
        case 124: return CGSize(width: step, height: 0)  // →
        case 125: return CGSize(width: 0, height: -step) // ↓
        case 126: return CGSize(width: 0, height: step)  // ↑
        default: return nil
        }
    }
}

// MARK: - Editor de texto en línea

/// `NSTextView` sin márgenes para que el texto que se escribe coincida con el que se dibuja.
private final class InlineTextEditor: NSTextView {

    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonSetup()
    }

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        commonSetup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) no está soportado")
    }

    private func commonSetup() {
        drawsBackground = false
        isRichText = false
        isEditable = true
        isSelectable = true
        allowsUndo = true
        textContainerInset = .zero
        textContainer?.lineFragmentPadding = 0
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
    }

    func configure(font: NSFont, color: NSColor) {
        self.font = font
        textColor = color
        insertionPointColor = color
    }

    /// ↩ confirma el texto.
    override func insertNewline(_ sender: Any?) {
        onCommit?()
    }

    /// ⌥↩ inserta un salto de línea real en lugar de confirmar.
    override func insertNewlineIgnoringFieldEditor(_ sender: Any?) {
        super.insertNewline(sender)
    }

    /// Esc descarta el texto en curso.
    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
