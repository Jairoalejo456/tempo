import AppKit
import SwiftUI

protocol EditorWindowDelegate: AnyObject {
    func editorRequestedCopy(_ controller: EditorWindowController)
    func editorRequestedSave(_ controller: EditorWindowController)
    /// Cerrar el editor conservando la captura como miniatura flotante.
    func editorRequestedReturnToThumbnail(_ controller: EditorWindowController)
    /// Descartar la captura por completo.
    func editorRequestedDiscard(_ controller: EditorWindowController)
}

/// Ventana del editor: barra de herramientas arriba y la captura ocupando todo lo demás.
final class EditorWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {

    weak var editorDelegate: EditorWindowDelegate?
    let editorDocument: EditorDocument
    let sessionID: UUID

    private let canvas: CanvasView
    private var keyMonitor: Any?

    init(sessionID: UUID, document: EditorDocument) {
        self.sessionID = sessionID
        self.editorDocument = document
        self.canvas = CanvasView(document: document)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: EditorWindowController.preferredContentSize(for: document)),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Captura"
        window.titlebarAppearsTransparent = false
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 720, height: 300)
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
            document: editorDocument,
            onUndo: { [weak self] in self?.undoEdit(nil) },
            onRedo: { [weak self] in self?.redoEdit(nil) },
            onCopy: { [weak self] in self?.copyImage(nil) },
            onSave: { [weak self] in self?.saveImage(nil) },
            onZoomIn: { [weak self] in self?.canvas.zoomIn() },
            onZoomOut: { [weak self] in self?.canvas.zoomOut() },
            onZoomToFit: { [weak self] in self?.canvas.zoomToFit() }
        )
        let hosting = NSHostingView(rootView: toolbar)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        canvas.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(hosting)
        container.addSubview(canvas)

        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hosting.heightAnchor.constraint(equalToConstant: 46),

            canvas.topAnchor.constraint(equalTo: hosting.bottomAnchor),
            canvas.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        return container
    }

    /// Tamaño inicial: la captura a tamaño real si cabe, o ajustada a la pantalla.
    private static func preferredContentSize(for document: EditorDocument) -> CGSize {
        let image = document.capture.logicalSize
        let toolbarHeight: CGFloat = 46
        let chrome: CGFloat = 60
        let visible = (NSScreen.main?.visibleFrame.size) ?? CGSize(width: 1440, height: 900)
        let maxWidth = visible.width * 0.9
        let maxHeight = visible.height * 0.9 - chrome

        let scale = min(maxWidth / image.width, (maxHeight - toolbarHeight) / image.height, 1)
        return CGSize(width: max(760, (image.width * scale).rounded() + 32),
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
        canvas.commitTextEditor()
        window?.orderOut(nil)
    }

    /// Confirma cualquier texto pendiente antes de exportar.
    func flushPendingEdits() {
        canvas.commitTextEditor()
    }

    // MARK: - Acciones (también accesibles desde el menú principal)

    @IBAction func copyImage(_ sender: Any?) {
        editorDelegate?.editorRequestedCopy(self)
    }

    @IBAction func saveImage(_ sender: Any?) {
        editorDelegate?.editorRequestedSave(self)
    }

    @IBAction func undoEdit(_ sender: Any?) {
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
        case #selector(copyImage(_:)): return !canvas.isEditingText
        default: return true
        }
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

        // Esc: cancela el texto en edición o vuelve a la miniatura.
        if event.keyCode == 53 {
            if canvas.isEditingText {
                canvas.cancelTextEditor()
            } else {
                editorDelegate?.editorRequestedReturnToThumbnail(self)
            }
            return true
        }

        // Mientras se escribe un texto, las teclas pertenecen al texto.
        guard !canvas.isEditingText else { return false }
        guard modifiers.isEmpty || modifiers == .shift else { return false }
        guard let characters = event.charactersIgnoringModifiers?.lowercased(), !characters.isEmpty else { return false }

        if let tool = EditorTool.allCases.first(where: { $0.shortcutKey == characters }) {
            editorDocument.tool = tool
            return true
        }

        if let index = Int(characters), (1...AnnotationColor.palette.count).contains(index) {
            editorDocument.color = AnnotationColor.palette[index - 1]
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

    private func adjustWeight(by delta: Int) {
        let weights = LineWeight.allCases
        let current = weights.firstIndex { abs($0.lineWidth - editorDocument.lineWidth) < 0.01 } ?? 1
        let next = min(max(current + delta, 0), weights.count - 1)
        editorDocument.lineWidth = weights[next].lineWidth
        editorDocument.fontSize = weights[next].fontSize
    }

    // MARK: - NSWindowDelegate

    /// Cerrar la ventana no destruye la captura: vuelve a su miniatura flotante.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        editorDelegate?.editorRequestedReturnToThumbnail(self)
        return false
    }
}
