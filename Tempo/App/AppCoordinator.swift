import AppKit
import Foundation

/// Orquesta el flujo completo: capturar, mostrar la miniatura, abrir el editor y entregar
/// la imagen final al portapapeles, al disco o a otra aplicación mediante arrastre.
final class AppCoordinator: NSObject {

    static let shared = AppCoordinator()

    private var sessions: [CaptureSession] = []
    private let regionSelection = RegionSelectionController()
    private var isCapturing = false

    private override init() {
        super.init()
    }

    var hasActiveSession: Bool { !sessions.isEmpty }

    // MARK: - Captura

    func captureFullScreen() {
        guard ensurePermission() else { return }
        guard !isCapturing, !regionSelection.isActive else { return }
        isCapturing = true

        let screen = ScreenCaptureService.screenUnderCursor()
        Task { @MainActor in
            defer { self.isCapturing = false }
            do {
                let capture = try await ScreenCaptureService.captureFullScreen(screen: screen)
                self.present(capture: capture, on: screen)
            } catch {
                self.report(error)
            }
        }
    }

    func captureRegion() {
        guard ensurePermission() else { return }
        guard !isCapturing, !regionSelection.isActive else { return }

        regionSelection.begin { [weak self] result in
            guard let self else { return }
            // Cancelar la selección es una operación válida: no ocurre nada.
            guard let (screen, rect) = result else { return }

            self.isCapturing = true
            Task { @MainActor in
                defer { self.isCapturing = false }
                do {
                    let capture = try await ScreenCaptureService.captureRegion(screen: screen, regionInScreen: rect)
                    self.present(capture: capture, on: screen)
                } catch {
                    self.report(error)
                }
            }
        }
    }

    /// Abre una captura de ejemplo para poder probar el editor sin necesidad del permiso de
    /// grabación de pantalla. Se activa con `--demo`.
    @MainActor
    func presentDemoCapture(openingEditor: Bool = false, withSampleAnnotations: Bool = false) {
        present(capture: SampleRenderer.makeSyntheticCapture(), on: NSScreen.main)
        guard let session = sessions.last else { return }
        if withSampleAnnotations {
            SampleRenderer.addSampleAnnotations(to: session.document)
        }
        guard openingEditor else { return }
        openEditor(for: session)
    }

    // MARK: - Presentación

    @MainActor
    private func present(capture: CaptureImage, on screen: NSScreen?) {
        let session = CaptureSession(capture: capture, screen: screen)
        sessions.append(session)
        showThumbnail(for: session)
        prewarmDragFile(for: session)
    }

    /// Componer una pantalla completa Retina cuesta unos milisegundos que se notarían justo
    /// al empezar a arrastrar, así que el archivo se prepara en segundo plano en cuanto la
    /// captura existe. Si el usuario anota algo, se regenera bajo demanda.
    private func prewarmDragFile(for session: CaptureSession) {
        let capture = session.document.capture
        let date = capture.createdAt
        DispatchQueue.global(qos: .userInitiated).async {
            guard let image = try? ImageExporter.compose(capture: capture, annotations: []),
                  let url = try? ImageExporter.writeTemporaryFile(image: image, date: date) else { return }
            DispatchQueue.main.async {
                // Si entretanto se anotó o se cerró la captura, el archivo ya no sirve.
                guard session.dragFileURL == nil, session.document.annotations.isEmpty,
                      self.sessions.contains(where: { $0.id == session.id }) else {
                    try? FileManager.default.removeItem(at: url)
                    return
                }
                session.dragFileURL = url
                session.dragFileAnnotations = []
            }
        }
    }

    @MainActor
    private func showThumbnail(for session: CaptureSession) {
        let image = thumbnailImage(for: session)
        let controller: ThumbnailWindowController
        if let existing = session.thumbnail {
            existing.update(image: image)
            controller = existing
        } else {
            controller = ThumbnailWindowController(sessionID: session.id, image: image)
            controller.delegate = self
            session.thumbnail = controller
        }
        restackThumbnails()
        controller.show()
    }

    /// Vista previa de la miniatura: la captura con las anotaciones ya aplicadas.
    private func thumbnailImage(for session: CaptureSession) -> NSImage {
        let capture = session.document.capture
        if session.document.hasAnnotations,
           let composed = try? ImageExporter.compose(document: session.document) {
            return NSImage(cgImage: composed, size: capture.logicalSize)
        }
        return NSImage(cgImage: capture.cgImage, size: capture.logicalSize)
    }

    /// Reordena las miniaturas visibles apilándolas desde la esquina inferior derecha.
    private func restackThumbnails() {
        var indexByScreen: [ObjectIdentifier: Int] = [:]
        for session in sessions {
            guard let thumbnail = session.thumbnail, !session.isEditorVisible else { continue }
            let screen = session.screen ?? NSScreen.main
            guard let screen else { continue }
            let key = ObjectIdentifier(screen)
            let index = indexByScreen[key, default: 0]
            thumbnail.position(on: screen, stackIndex: index)
            indexByScreen[key] = index + 1
        }
    }

    // MARK: - Editor

    @MainActor
    private func openEditor(for session: CaptureSession) {
        session.thumbnail?.hide()

        let controller: EditorWindowController
        if let existing = session.editor {
            controller = existing
        } else {
            controller = EditorWindowController(sessionID: session.id, document: session.document)
            controller.editorDelegate = self
            session.editor = controller
        }
        controller.present()
        restackThumbnails()
    }

    @MainActor
    private func returnToThumbnail(_ session: CaptureSession) {
        session.editor?.hideWindow()
        showThumbnail(for: session)
        updateActivationPolicy()
    }

    // MARK: - Salida

    @MainActor
    private func copy(_ session: CaptureSession) {
        session.editor?.flushPendingEdits()
        do {
            let image = try ImageExporter.compose(document: session.document)
            try ImageExporter.copyToPasteboard(image: image)
            HUDPresenter.show("Copiado al portapapeles", symbol: "checkmark.circle.fill", on: session.screen)
            // Copiar cierra el flujo: la imagen ya está lista para pegarse con ⌘V.
            close(session)
        } catch {
            report(error)
        }
    }

    @MainActor
    private func save(_ session: CaptureSession) {
        session.editor?.flushPendingEdits()

        let image: CGImage
        do {
            image = try ImageExporter.compose(document: session.document)
        } catch {
            report(error)
            return
        }

        let preferences = Preferences.shared
        let fileName = ImageExporter.suggestedFileName(for: session.document.capture.createdAt)

        // Guardado directo: sin panel, a la carpeta configurada en los ajustes.
        if preferences.saveMode == .direct, preferences.saveFolderExists {
            do {
                let url = ImageExporter.availableURL(for: fileName, in: preferences.saveFolder)
                try ImageExporter.write(image: image, to: url)
                HUDPresenter.show("Guardado en \(preferences.saveFolder.lastPathComponent)",
                                  symbol: "checkmark.circle.fill", on: session.screen)
                close(session)
            } catch {
                report(error)
            }
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = fileName
        panel.message = "Elige dónde guardar la captura"
        // El panel se abre en la carpeta configurada, aunque se pregunte cada vez.
        if preferences.saveFolderExists {
            panel.directoryURL = preferences.saveFolder
        }

        NSApp.activate(ignoringOtherApps: true)

        let handler: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self else { return }
            // Cancelar el guardado deja la captura intacta y disponible.
            guard response == .OK, let url = panel.url else { return }
            do {
                try ImageExporter.write(image: image, to: url)
                // La carpeta elegida pasa a ser la propuesta la próxima vez.
                Preferences.shared.saveFolder = url.deletingLastPathComponent()
                HUDPresenter.show("Guardado", symbol: "checkmark.circle.fill", on: session.screen)
                self.close(session)
            } catch {
                self.report(error)
            }
        }

        if let window = session.editor?.window, window.isVisible {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            panel.begin(completionHandler: handler)
        }
    }

    // MARK: - Cierre

    @MainActor
    func close(_ session: CaptureSession) {
        session.editor?.hideWindow()
        session.editor?.window?.close()
        session.editor = nil
        session.thumbnail?.close(animated: true)
        session.thumbnail = nil
        if let url = session.dragFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        sessions.removeAll { $0.id == session.id }
        restackThumbnails()
        updateActivationPolicy()
    }

    @MainActor
    func closeAll() {
        for session in sessions {
            close(session)
        }
    }

    /// La aplicación aparece en el Dock mientras hay un editor abierto, o siempre si el usuario
    /// lo ha pedido en los ajustes.
    func updateActivationPolicy() {
        let needsRegular = Preferences.shared.showsDockIcon
            || sessions.contains { $0.isEditorVisible }
            || PreferencesWindowController.isShowing
        let target: NSApplication.ActivationPolicy = needsRegular ? .regular : .accessory
        if NSApp.activationPolicy() != target {
            NSApp.setActivationPolicy(target)
        }
    }

    // MARK: - Permisos y errores

    @discardableResult
    private func ensurePermission() -> Bool {
        if ScreenCaptureService.hasPermission { return true }

        // Provoca el diálogo del sistema la primera vez.
        ScreenCaptureService.requestPermission()
        if ScreenCaptureService.hasPermission { return true }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Falta el permiso de Grabación de pantalla"
        alert.informativeText = """
        Para capturar la pantalla, activa Tempo en:
        Ajustes del Sistema › Privacidad y seguridad › Grabación de pantalla.

        Tras concederlo, vuelve a intentar la captura.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Abrir Ajustes")
        alert.addButton(withTitle: "Cancelar")
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
        return false
    }

    private func report(_ error: Error) {
        NSLog("[Tempo] Error: \(error.localizedDescription)")
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "No se pudo completar la captura"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Aceptar")
        alert.runModal()
    }

    private func session(with id: UUID) -> CaptureSession? {
        sessions.first { $0.id == id }
    }
}

// MARK: - Miniatura

extension AppCoordinator: ThumbnailWindowDelegate {

    func thumbnailRequestedOpen(_ controller: ThumbnailWindowController) {
        guard let session = session(with: controller.sessionID) else { return }
        Task { @MainActor in self.openEditor(for: session) }
    }

    func thumbnailRequestedDismiss(_ controller: ThumbnailWindowController) {
        guard let session = session(with: controller.sessionID) else { return }
        Task { @MainActor in self.close(session) }
    }

    func thumbnailFileURLForDragging(_ controller: ThumbnailWindowController) -> URL? {
        guard let session = session(with: controller.sessionID) else { return nil }

        // Se reutiliza el archivo si las anotaciones no han cambiado desde el último arrastre.
        if let url = session.dragFileURL,
           session.dragFileAnnotations == session.document.annotations,
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }

        do {
            if let previous = session.dragFileURL {
                try? FileManager.default.removeItem(at: previous)
            }
            let image = try ImageExporter.compose(document: session.document)
            let url = try ImageExporter.writeTemporaryFile(image: image, date: session.document.capture.createdAt)
            session.dragFileURL = url
            session.dragFileAnnotations = session.document.annotations
            return url
        } catch {
            NSLog("[Tempo] No se pudo preparar el archivo para arrastrar: \(error.localizedDescription)")
            return nil
        }
    }

    func thumbnailDidFinishDrag(_ controller: ThumbnailWindowController, accepted: Bool) {
        // La miniatura se conserva tras arrastrar para poder soltarla en varios sitios.
    }

    func thumbnailRequestedCopy(_ controller: ThumbnailWindowController) {
        guard let session = session(with: controller.sessionID) else { return }
        Task { @MainActor in self.copy(session) }
    }

    func thumbnailRequestedSave(_ controller: ThumbnailWindowController) {
        guard let session = session(with: controller.sessionID) else { return }
        Task { @MainActor in self.save(session) }
    }
}

// MARK: - Editor

extension AppCoordinator: EditorWindowDelegate {

    func editorRequestedCopy(_ controller: EditorWindowController) {
        guard let session = session(with: controller.sessionID) else { return }
        Task { @MainActor in self.copy(session) }
    }

    func editorRequestedSave(_ controller: EditorWindowController) {
        guard let session = session(with: controller.sessionID) else { return }
        Task { @MainActor in self.save(session) }
    }

    func editorRequestedReturnToThumbnail(_ controller: EditorWindowController) {
        guard let session = session(with: controller.sessionID) else { return }
        Task { @MainActor in self.returnToThumbnail(session) }
    }

    func editorRequestedDiscard(_ controller: EditorWindowController) {
        guard let session = session(with: controller.sessionID) else { return }
        Task { @MainActor in self.close(session) }
    }
}
