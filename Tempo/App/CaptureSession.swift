import AppKit
import Foundation

/// Una captura viva dentro de la aplicación.
///
/// La sesión es la dueña de la imagen y de sus anotaciones; la miniatura y el editor son sólo
/// dos formas de mostrarla. Por eso cerrar el editor no destruye nada: la sesión sigue ahí.
final class CaptureSession {
    let id = UUID()
    let document: EditorDocument
    /// Pantalla en la que se hizo la captura; determina dónde aparece la miniatura.
    let screen: NSScreen?

    var thumbnail: ThumbnailWindowController?
    var editor: EditorWindowController?

    /// Archivo temporal creado para arrastrar; se borra al cerrar la sesión.
    var dragFileURL: URL?
    /// Anotaciones con las que se generó `dragFileURL`, para no reescribirlo si nada cambió.
    var dragFileAnnotations: [Annotation]?

    init(capture: CaptureImage, screen: NSScreen?) {
        self.document = EditorDocument(capture: capture)
        self.screen = screen
    }

    var isEditorVisible: Bool {
        editor?.window?.isVisible == true
    }
}
