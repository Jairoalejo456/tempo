import AppKit
import Combine
import SwiftUI

protocol EditorWindowDelegate: AnyObject {
    func editorRequestedCopy(_ controller: EditorWindowController)
    func editorRequestedSave(_ controller: EditorWindowController)
    /// Copiar todas las capturas unidas en una sola imagen.
    func editorRequestedCopyAll(_ controller: EditorWindowController)
    /// Guardar cada captura en su propio archivo.
    func editorRequestedSaveAll(_ controller: EditorWindowController)
    /// Cerrar el editor conservando la captura como miniatura flotante.
    func editorRequestedReturnToThumbnail(_ controller: EditorWindowController)
    /// Descartar la captura por completo.
    func editorRequestedDiscard(_ controller: EditorWindowController)
}

/// Ventana del editor: barra de herramientas arriba y la captura ocupando todo lo demás.
final class EditorWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {

    weak var editorDelegate: EditorWindowDelegate?

    /// Capturas que se están editando. Puede ser una sola o varias apiladas.
    let stack: EditorStack

    /// Documento activo: sobre él actúan la barra, los atajos y las acciones de salida.
    var editorDocument: EditorDocument { stack.active }

    private var canvases: [UUID: CanvasView] = [:]
    /// Contenedor donde se muestra el lienzo de la captura activa.
    private var canvasHost: NSView?
    private var sidebarView: NSView?
    private var keyMonitor: Any?
    private var cancellables: Set<AnyCancellable> = []

    /// El lienzo de la captura activa.
    private var canvas: CanvasView {
        canvases[stack.activeID] ?? canvases.values.first!
    }

    /// Renumeración de contadores tecleando, sin cuadros ni confirmación.
    private lazy var counterEntry = CounterQuickEntry(stack: stack)

    init(stack: EditorStack) {
        self.stack = stack

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: EditorWindowController.preferredContentSize(for: stack)),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        // El título es el nombre de la aplicación, para que se reconozca de un vistazo en el
        // conmutador de ventanas y en la barra de título.
        window.title = Preferences.appName
        window.titlebarAppearsTransparent = false
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 880, height: 320)
        window.tabbingMode = .disallowed

        super.init(window: window)

        window.delegate = self
        window.contentView = makeContentView()
        window.center()
        shouldCascadeWindows = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) no está soportado")
    }

    deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }

    // MARK: - Construcción de la interfaz

    private func makeContentView() -> NSView {
        let container = NSView()

        let toolbar = EditorToolbarView(
            stack: stack,
            onUndo: { [weak self] in self?.undoEdit(nil) },
            onRedo: { [weak self] in self?.redoEdit(nil) },
            onCopy: { [weak self] in self?.copyImage(nil) },
            onSave: { [weak self] in self?.saveImage(nil) },
            onCopyAll: { [weak self] in self?.copyAllCombined(nil) },
            onSaveAll: { [weak self] in self?.saveAllSeparately(nil) },
            onZoomIn: { [weak self] in self?.canvas.zoomIn() },
            onZoomOut: { [weak self] in self?.canvas.zoomOut() },
            onZoomToFit: { [weak self] in self?.canvas.zoomToFit() },
            onSelect: { [weak self] id in self?.activate(id) }
        )
        let hosting = NSHostingView(rootView: toolbar)
        hosting.translatesAutoresizingMaskIntoConstraints = false

        let content = makeEditingArea()
        content.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(hosting)
        container.addSubview(content)

        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hosting.heightAnchor.constraint(equalToConstant: EditorMetrics.toolbarHeight),

            content.topAnchor.constraint(equalTo: hosting.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        return container
    }

    /// Sólo se muestra la captura activa, ocupando todo el lienzo; las demás se eligen desde
    /// la tira lateral de miniaturas.
    ///
    /// Cada captura conserva su propio lienzo aunque no esté visible, de modo que al volver a
    /// ella siguen intactos su zoom, su desplazamiento y lo que tuviera seleccionado.
    private func makeEditingArea() -> NSView {
        let area = NSView()

        let host = NSView()
        host.translatesAutoresizingMaskIntoConstraints = false
        canvasHost = host

        if stack.holdsSeveral {
            let sidebar = NSHostingView(rootView: StackSidebar(stack: stack) { [weak self] id in
                self?.activate(id)
            })
            sidebar.translatesAutoresizingMaskIntoConstraints = false
            area.addSubview(sidebar)
            area.addSubview(host)
            // La tira va a la derecha: deja el lienzo pegado al borde izquierdo, que es por
            // donde se empieza a mirar una captura.
            NSLayoutConstraint.activate([
                sidebar.topAnchor.constraint(equalTo: area.topAnchor),
                sidebar.bottomAnchor.constraint(equalTo: area.bottomAnchor),
                sidebar.trailingAnchor.constraint(equalTo: area.trailingAnchor),
                sidebar.widthAnchor.constraint(equalToConstant: StackSidebar.width),

                host.topAnchor.constraint(equalTo: area.topAnchor),
                host.bottomAnchor.constraint(equalTo: area.bottomAnchor),
                host.leadingAnchor.constraint(equalTo: area.leadingAnchor),
                host.trailingAnchor.constraint(equalTo: sidebar.leadingAnchor)
            ])
            sidebarView = sidebar
        } else {
            area.addSubview(host)
            NSLayoutConstraint.activate([
                host.topAnchor.constraint(equalTo: area.topAnchor),
                host.bottomAnchor.constraint(equalTo: area.bottomAnchor),
                host.leadingAnchor.constraint(equalTo: area.leadingAnchor),
                host.trailingAnchor.constraint(equalTo: area.trailingAnchor)
            ])
        }

        showCanvas(for: stack.activeID)
        return area
    }

    /// Pone en el lienzo la captura indicada, creando su vista la primera vez.
    private func showCanvas(for id: UUID) {
        guard let host = canvasHost, let document = stack.document(with: id) else { return }
        let canvas = canvases[id] ?? makeCanvas(for: document)
        guard canvas.superview !== host else { return }

        for existing in host.subviews { existing.removeFromSuperview() }
        canvas.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(canvas)
        NSLayoutConstraint.activate([
            canvas.topAnchor.constraint(equalTo: host.topAnchor),
            canvas.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            canvas.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: host.trailingAnchor)
        ])
        window?.makeFirstResponder(canvas)
    }

    private func makeCanvas(for document: EditorDocument) -> CanvasView {
        let canvas = CanvasView(document: document)
        canvas.onActivate = { [weak self] in self?.activate(document.id) }
        canvases[document.id] = canvas
        return canvas
    }

    /// Hace activa una captura y la trae al lienzo.
    private func activate(_ id: UUID) {
        guard stack.activeID != id else { return }
        // Lo que se estuviera escribiendo en la captura anterior se confirma antes de dejarla.
        canvases[stack.activeID]?.commitTextEditor()
        stack.activate(id)
        showCanvas(for: id)
    }

    /// Quita del editor las capturas que ya no están en la pila.
    private func rebuildStack() {
        for (id, canvas) in canvases where stack.document(with: id) == nil {
            canvas.removeFromSuperview()
            canvases.removeValue(forKey: id)
        }
        showCanvas(for: stack.activeID)
    }


    /// Rehace la pila cuando el coordinador ha añadido capturas nuevas.
    func refreshAfterExternalChange() {
        // La tira lateral aparece en cuanto hay más de una captura, así que la vista se
        // reconstruye si acaba de dejar de haber una sola.
        if stack.holdsSeveral, sidebarView == nil {
            window?.contentView = makeContentView()
        } else {
            showCanvas(for: stack.activeID)
        }
    }

    /// Activa una captura y la trae a la vista.
    func focus(on id: UUID) {
        activate(id)
    }

    /// Quita una captura de la pila tras copiarla o guardarla.
    /// - Returns: `false` si era la última y la ventana debe cerrarse.
    @discardableResult
    func removeFromStack(_ id: UUID) -> Bool {
        let survives = stack.remove(id)
        if survives { rebuildStack() }
        return survives
    }

    @IBAction func undoEdit(_ sender: Any?) {
        counterEntry.finish()
        canvas.commitTextEditor()
        editorDocument.undo()
    }

    @IBAction func redoEdit(_ sender: Any?) {
        editorDocument.redo()
    }

    @IBAction func zoomIn(_ sender: Any?) {
        canvas.zoomIn()
    }

    @IBAction func zoomOut(_ sender: Any?) {
        canvas.zoomOut()
    }

    @IBAction func zoomToFit(_ sender: Any?) {
        canvas.zoomToFit()
    }

    @IBAction func zoomToActualSize(_ sender: Any?) {
        canvas.zoomToActualSize()
    }

    @IBAction func returnToThumbnail(_ sender: Any?) {
        editorDelegate?.editorRequestedReturnToThumbnail(self)
    }

    @IBAction func discardCapture(_ sender: Any?) {
        editorDelegate?.editorRequestedDiscard(self)
    }

    /// `true` mientras el usuario escribe una anotación de texto.
    var isEditingText: Bool { canvas.isEditingText }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(undoEdit(_:)): return editorDocument.canUndo
        case #selector(redoEdit(_:)): return editorDocument.canRedo
        // Mientras se escribe un texto, ⌘C debe copiar texto: lo atiende el campo de edición.
        case #selector(copyImage(_:)): return !isEditingText
        default: return true
        }
    }

    /// Tamaño inicial: la captura a tamaño real si cabe, o ajustada a la pantalla.
    private static func preferredContentSize(for stack: EditorStack) -> CGSize {
        // Con varias capturas la ventana nace más ancha: la tira lateral ocupa su sitio y la
        // captura activa no debería quedarse estrecha por ello.
        let sidebar = stack.holdsSeveral ? StackSidebar.width : 0
        let image = stack.active.capture.logicalSize
        let toolbarHeight = EditorMetrics.toolbarHeight
        let chrome: CGFloat = 60
        let visible = (NSScreen.main?.visibleFrame.size) ?? CGSize(width: 1440, height: 900)
        let maxWidth = visible.width * 0.9
        let maxHeight = visible.height * 0.9 - chrome

        let scale = min(maxWidth / image.width, (maxHeight - toolbarHeight) / image.height, 1)
        return CGSize(width: max(940, (image.width * scale).rounded() + 32 + sidebar),
                      height: max(320, (image.height * scale).rounded() + toolbarHeight + 32))
    }

    // MARK: - Presentación

    func present() {
        installKeyMonitorIfNeeded()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(canvas)
    }

    func hideWindow() {
        flushPendingEdits()
        window?.orderOut(nil)
    }

    /// Confirma cualquier texto o número a medio escribir antes de exportar.
    func flushPendingEdits() {
        counterEntry.finish()
        canvas.commitTextEditor()
        // La selección no debe salir dibujada en la imagen final.
        editorDocument.select(nil)
    }

    // MARK: - Acciones sobre la captura activa

    @IBAction func copyImage(_ sender: Any?) {
        editorDelegate?.editorRequestedCopy(self)
    }

    @IBAction func saveImage(_ sender: Any?) {
        editorDelegate?.editorRequestedSave(self)
    }

    @IBAction func copyAllCombined(_ sender: Any?) {
        editorDelegate?.editorRequestedCopyAll(self)
    }

    @IBAction func saveAllSeparately(_ sender: Any?) {
        editorDelegate?.editorRequestedSaveAll(self)
    }


    // MARK: - Atajos de una sola tecla

    /// Se usa un monitor local en lugar de ítems de menú porque las teclas sin modificadores
    /// deben llegar al campo de texto cuando el usuario está escribiendo una anotación.
    private func installKeyMonitorIfNeeded() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard self.window?.isKeyWindow == true else { return event }
            return self.handle(event) ? nil : event
        }
    }

    private func handle(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // ↩ confirma el encuadre propuesto.
        if event.keyCode == 36, canvas.isCropping, !canvas.isEditingText {
            canvas.applyCrop()
            return true
        }

        // Esc va deshaciendo estados, del más concreto al más general.
        if event.keyCode == 53 {
            if canvas.isCropping {
                canvas.cancelCrop()
            } else if counterEntry.isTyping {
                counterEntry.finish()
            } else if canvas.isEditingText {
                canvas.cancelTextEditor()
            } else if editorDocument.selectedAnnotation != nil {
                editorDocument.select(nil)
            } else {
                editorDelegate?.editorRequestedReturnToThumbnail(self)
            }
            return true
        }

        // ⌥↑ y ⌥↓ saltan entre capturas cuando hay varias apiladas.
        if stack.holdsSeveral, modifiers == .option, event.keyCode == 126 || event.keyCode == 125 {
            let index = stack.documents.firstIndex { $0.id == stack.activeID } ?? 0
            let target = min(max(index + (event.keyCode == 126 ? -1 : 1), 0), stack.count - 1)
            activate(stack.documents[target].id)
            return true
        }

        // Mientras se escribe un texto, las teclas pertenecen a ese campo.
        guard !canvas.isEditingText else { return false }
        guard modifiers.isEmpty || modifiers == .shift else { return false }
        guard let characters = event.charactersIgnoringModifiers?.lowercased(), !characters.isEmpty else { return false }

        if let tool = EditorTool.allCases.first(where: { $0.shortcutKey == characters }) {
            editorDocument.tool = tool
            return true
        }

        // Con un contador seleccionado, teclear un número lo cambia al instante. Es lo que se
        // espera al escribir sobre algo que muestra una cifra, y prevalece sobre el atajo de
        // color mientras ese contador siga elegido.
        if let digit = characters.first, digit.isNumber, counterEntry.type(digit) {
            return true
        }

        // Mientras se teclea un número, ⌫ corrige el último dígito en lugar de borrar el
        // contador entero.
        if event.keyCode == 51, counterEntry.deleteLastDigit() {
            return true
        }

        if let index = Int(characters), (1...AnnotationColor.palette.count).contains(index) {
            editorDocument.color = AnnotationColor.palette[index - 1]
            editorDocument.applyColorToSelection()
            return true
        }

        switch characters {
        case "[":
            adjustWeight(by: -1)
            return true
        case "]":
            adjustWeight(by: 1)
            return true
        default:
            return false
        }
    }

    /// `[` y `]` ajustan lo que corresponda a lo que se está tocando: la intensidad del blur,
    /// el grosor del lápiz, o el tamaño del resto de herramientas.
    private func adjustWeight(by delta: Int) {
        let tool = editorDocument.selectedAnnotation.map { EditorTool.annotate($0.tool) } ?? editorDocument.tool

        switch tool {
        case .annotate(.blur):
            let step: CGFloat = 1 / CGFloat(CaptureImage.blurLevels) * 2
            editorDocument.blurIntensity = min(max(editorDocument.blurIntensity + CGFloat(delta) * step, 0), 1)
            editorDocument.applyBlurIntensityToSelection()
        case .annotate(.pencil):
            let range = EditorDocument.pencilWidthRange
            editorDocument.lineWidth = min(max(editorDocument.lineWidth + CGFloat(delta), range.lowerBound),
                                           range.upperBound)
            editorDocument.applyLineWidthToSelection()
        default:
            let weights = LineWeight.allCases
            let current = weights.firstIndex { abs($0.lineWidth - editorDocument.lineWidth) < 0.01 } ?? 1
            let next = min(max(current + delta, 0), weights.count - 1)
            editorDocument.lineWidth = weights[next].lineWidth
            editorDocument.fontSize = weights[next].fontSize
            editorDocument.applyWeightToSelection()
        }
    }

    // MARK: - NSWindowDelegate

    /// Cerrar la ventana no destruye la captura: vuelve a su miniatura flotante.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        editorDelegate?.editorRequestedReturnToThumbnail(self)
        return false
    }
}
