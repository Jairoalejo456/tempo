import Combine
import CoreGraphics
import Foundation

/// Estado editable de una captura: las anotaciones, la herramienta y el color activos,
/// y las pilas de deshacer/rehacer. No sabe nada de ventanas ni de AppKit.
final class EditorDocument: ObservableObject {
    let capture: CaptureImage
    let id = UUID()

    @Published private(set) var annotations: [Annotation] = []

    /// Herramienta activa. El editor abre siempre en modo puntero: mirar la captura y moverse
    /// por ella no debe ensuciarla con una anotación accidental al primer clic.
    @Published var tool: EditorTool = .navigate
    @Published var color: AnnotationColor = .red
    @Published var lineWidth: CGFloat = 4
    @Published var fontSize: CGFloat = 28

    /// Anotación que se está creando con el ratón; se dibuja pero aún no forma parte del historial.
    @Published var draft: Annotation?

    // MARK: - Presentación

    /// Zoom aplicado por el usuario, relativo al ajuste a la ventana (1 = ajustada).
    @Published var zoomFactor: CGFloat = 1
    /// Escala a la que la captura cabe en la ventana; la calcula el lienzo.
    @Published var fitScale: CGFloat = 1

    /// Zoom efectivo respecto al tamaño real de la captura, que es lo que se muestra al usuario.
    var effectiveZoom: CGFloat { fitScale * zoomFactor }

    // Publicadas para que la barra de herramientas active o desactive los botones al instante.
    @Published private var undoStack: [[Annotation]] = []
    @Published private var redoStack: [[Annotation]] = []

    init(capture: CaptureImage) {
        self.capture = capture
    }

    var currentStyle: AnnotationStyle {
        AnnotationStyle(color: color, lineWidth: lineWidth, fontSize: fontSize)
    }

    /// Lo que debe dibujarse ahora mismo: historial + borrador en curso.
    var renderableAnnotations: [Annotation] {
        draft.map { annotations + [$0] } ?? annotations
    }

    // MARK: - Contadores

    /// Siguiente número de contador. Se deriva de las anotaciones existentes, así que
    /// deshacer un contador devuelve automáticamente la numeración al valor anterior.
    var nextCounterNumber: Int {
        let used = annotations.compactMap { annotation -> Int? in
            if case let .counter(_, number) = annotation.shape { return number }
            return nil
        }
        return (used.max() ?? 0) + 1
    }

    // MARK: - Mutaciones con historial

    /// Aplica un cambio registrándolo en el historial de deshacer.
    func perform(_ change: (inout [Annotation]) -> Void) {
        let snapshot = annotations
        var copy = annotations
        change(&copy)
        guard copy != annotations else { return }
        undoStack.append(snapshot)
        redoStack.removeAll()
        annotations = copy
    }

    func add(_ annotation: Annotation) {
        guard annotation.isMeaningful else { return }
        perform { $0.append(annotation) }
    }

    func removeLast() {
        guard !annotations.isEmpty else { return }
        perform { $0.removeLast() }
    }

    func removeAll() {
        guard !annotations.isEmpty else { return }
        perform { $0.removeAll() }
    }

    // MARK: - Deshacer / rehacer

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(annotations)
        annotations = previous
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(annotations)
        annotations = next
    }

    /// `true` cuando el documento tiene cambios sin exportar (se usa al cerrar el editor).
    var hasAnnotations: Bool { !annotations.isEmpty }
}
