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

    /// Editor de texto en línea, cuando la herramienta de texto está activa.
    private var textEditor: InlineTextEditor?
    private var textEditorOrigin: CGPoint?

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

    /// Escala a la que se muestra la captura para caber en la ventana (nunca amplía).
    var displayScale: CGFloat {
        let available = bounds.insetBy(dx: padding, dy: padding).size
        let image = document.capture.logicalSize
        guard image.width > 0, image.height > 0, available.width > 0, available.height > 0 else { return 1 }
        return min(available.width / image.width, available.height / image.height, 1)
    }

    /// Rectángulo, en coordenadas de la vista, donde se dibuja la captura.
    var imageFrame: CGRect {
        let scale = displayScale
        let size = CGSize(width: document.capture.logicalSize.width * scale,
                          height: document.capture.logicalSize.height * scale)
        return CGRect(x: ((bounds.width - size.width) / 2).rounded(),
                      y: ((bounds.height - size.height) / 2).rounded(),
                      width: size.width,
                      height: size.height)
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
    }

    override func resetCursorRects() {
        addCursorRect(imageFrame, cursor: .crosshair)
    }

    override func layout() {
        super.layout()
        discardCursorRects()
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    // MARK: - Gestos

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)

        // Si había un texto en edición, un clic fuera lo confirma.
        if textEditor != nil {
            commitTextEditor()
            return
        }

        let point = clamped(imagePoint(from: convert(event.locationInWindow, from: nil)))
        guard imageFrame.insetBy(dx: -2, dy: -2).contains(convert(event.locationInWindow, from: nil)) else { return }

        switch document.tool {
        case .counter:
            let annotation = Annotation(shape: .counter(center: point, number: document.nextCounterNumber),
                                        style: document.currentStyle)
            document.add(annotation)
        case .text:
            beginTextEditing(at: point)
        case .arrow, .rectangle, .ellipse, .blur, .pencil:
            gestureAnchor = point
            isDrawing = true
            document.draft = makeDraft(from: point, to: point, points: [point])
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDrawing, let anchor = gestureAnchor else { return }
        var point = clamped(imagePoint(from: convert(event.locationInWindow, from: nil)))

        if event.modifierFlags.contains(.shift) {
            point = constrained(point, from: anchor, tool: document.tool)
        }

        if document.tool == .pencil, case let .pencil(existing)? = document.draft?.shape {
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

    override func mouseUp(with event: NSEvent) {
        defer {
            isDrawing = false
            gestureAnchor = nil
        }
        guard isDrawing, let draft = document.draft else { return }
        document.draft = nil
        document.add(draft)
        needsDisplay = true
    }

    private func makeDraft(from: CGPoint, to: CGPoint, points: [CGPoint]) -> Annotation {
        let rect = CGRect(x: min(from.x, to.x), y: min(from.y, to.y),
                          width: abs(to.x - from.x), height: abs(to.y - from.y))
        let shape: AnnotationShape
        switch document.tool {
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

    // MARK: - Texto en línea

    var isEditingText: Bool { textEditor != nil }

    private func beginTextEditing(at point: CGPoint) {
        commitTextEditor()

        let style = document.currentStyle
        let scale = displayScale
        let font = NSFont.systemFont(ofSize: style.fontSize * scale, weight: .semibold)
        let lineHeight = ceil(font.ascender - font.descender + font.leading)

        let origin = viewPoint(from: point)
        let editor = InlineTextEditor(frame: CGRect(x: origin.x, y: origin.y,
                                                    width: max(120, bounds.maxX - origin.x - padding),
                                                    height: lineHeight))
        editor.configure(font: font, color: NSColor(cgColor: style.color.cgColor) ?? .systemRed)
        editor.onCommit = { [weak self] in self?.commitTextEditor() }
        editor.onCancel = { [weak self] in self?.cancelTextEditor() }

        addSubview(editor)
        window?.makeFirstResponder(editor)

        textEditor = editor
        textEditorOrigin = point
    }

    /// Confirma el texto en edición convirtiéndolo en anotación.
    @discardableResult
    func commitTextEditor() -> Bool {
        guard let editor = textEditor, let origin = textEditorOrigin else { return false }
        let string = editor.string
        textEditor = nil
        textEditorOrigin = nil
        editor.removeFromSuperview()
        window?.makeFirstResponder(self)

        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        document.add(Annotation(shape: .text(origin: origin, string: string), style: document.currentStyle))
        needsDisplay = true
        return true
    }

    func cancelTextEditor() {
        guard let editor = textEditor else { return }
        textEditor = nil
        textEditorOrigin = nil
        editor.removeFromSuperview()
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    // MARK: - Teclado

    override func keyDown(with event: NSEvent) {
        // Retroceso elimina la última anotación; Esc cierra el editor (lo gestiona la ventana).
        if event.keyCode == 51 || event.keyCode == 117 { // Delete / Fn+Delete
            document.removeLast()
            return
        }
        super.keyDown(with: event)
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
