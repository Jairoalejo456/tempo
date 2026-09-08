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
    /// Fuerza del difuminado que se aplicará a los siguientes blurs.
    @Published var blurIntensity: CGFloat = AnnotationStyle.defaultBlurIntensity

    /// Anotación que se está creando con el ratón; se dibuja pero aún no forma parte del historial.
    @Published var draft: Annotation?

    /// Anotación seleccionada, si hay alguna. Las anotaciones no quedan "estampadas": se pueden
    /// volver a elegir para moverlas, redimensionarlas, girarlas o cambiarles el estilo.
    @Published var selectedID: UUID?

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
        AnnotationStyle(color: color, lineWidth: lineWidth, fontSize: fontSize, blurIntensity: blurIntensity)
    }

    /// Rango de grosor del lápiz, que se ajusta con su deslizador.
    static let pencilWidthRange: ClosedRange<CGFloat> = 1...24

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
        select(annotation.id)
    }

    /// Registra una anotación recién colocada con el ratón.
    ///
    /// Además de añadirla, devuelve la herramienta al puntero: lo normal tras dibujar algo es
    /// querer ajustarlo, no dibujar otro igual. Con `keepingTool` se conserva la herramienta,
    /// que es lo cómodo para encadenar varios contadores o varios trazos.
    /// - Returns: `true` si la anotación llegó a añadirse.
    @discardableResult
    func place(_ annotation: Annotation, keepingTool: Bool = false) -> Bool {
        let countBefore = annotations.count
        add(annotation)
        guard annotations.count > countBefore else { return false }
        if !keepingTool {
            tool = .navigate
        }
        return true
    }

    // MARK: - Selección

    var selectedAnnotation: Annotation? {
        guard let selectedID else { return nil }
        return annotations.first { $0.id == selectedID }
    }

    func select(_ id: UUID?) {
        guard selectedID != id else { return }
        selectedID = id
        adoptStyleOfSelection()
    }

    /// Al elegir una anotación, los controles de la barra pasan a mostrar **sus** propiedades.
    ///
    /// Sin esto la barra mentía: podía marcar rojo mientras había seleccionado un texto azul, y
    /// entonces cambiar el tamaño le aplicaba de paso un color que el usuario no había pedido.
    private func adoptStyleOfSelection() {
        guard let annotation = selectedAnnotation else { return }
        if annotation.tool.usesColor {
            color = annotation.style.color
        }
        lineWidth = annotation.style.lineWidth
        fontSize = annotation.style.fontSize
        if annotation.tool == .blur {
            blurIntensity = annotation.style.blurIntensity
        }
    }

    /// Anotación bajo un punto, empezando por la de encima.
    func annotation(at point: CGPoint, tolerance: CGFloat) -> Annotation? {
        annotations.reversed().first { $0.hitTest(point, tolerance: tolerance) }
    }

    func deleteSelected() {
        guard let selectedID else { return }
        perform { $0.removeAll { $0.id == selectedID } }
        self.selectedID = nil
    }

    // MARK: - Cambios sobre una anotación existente

    /// Sustituye una anotación registrando el cambio en el historial.
    func replace(_ annotation: Annotation) {
        perform { list in
            guard let index = list.firstIndex(where: { $0.id == annotation.id }) else { return }
            list[index] = annotation
        }
    }

    /// Snapshot tomado al empezar un arrastre, para que toda la interacción cuente como una
    /// sola operación de deshacer en lugar de una por cada movimiento del ratón.
    private var interactionSnapshot: [Annotation]?

    func beginInteractiveChange() {
        guard interactionSnapshot == nil else { return }
        interactionSnapshot = annotations
    }

    /// Actualiza la anotación sin tocar el historial. Se usa durante el arrastre.
    func updateLive(_ annotation: Annotation) {
        guard let index = annotations.firstIndex(where: { $0.id == annotation.id }) else { return }
        annotations[index] = annotation
    }

    func endInteractiveChange() {
        guard let snapshot = interactionSnapshot else { return }
        interactionSnapshot = nil
        guard snapshot != annotations else { return }
        undoStack.append(snapshot)
        redoStack.removeAll()
    }

    // MARK: - Estilo de lo seleccionado

    /// Aplica el color activo a la anotación seleccionada, si la hay.
    func applyColorToSelection() {
        guard var annotation = selectedAnnotation, annotation.tool.usesColor else { return }
        annotation.style.color = color
        replace(annotation)
    }

    func applyWeightToSelection() {
        guard var annotation = selectedAnnotation else { return }
        annotation.style.lineWidth = lineWidth
        if annotation.tool == .text || annotation.tool == .counter {
            annotation.style.fontSize = fontSize
        }
        replace(annotation)
    }

    /// Aplica la intensidad de difuminado activa al blur seleccionado, si lo hay.
    func applyBlurIntensityToSelection() {
        guard var annotation = selectedAnnotation, annotation.tool == .blur else { return }
        annotation.style.blurIntensity = blurIntensity
        replace(annotation)
    }

    /// Aplica el grosor activo al trazo seleccionado, si lo hay.
    func applyLineWidthToSelection() {
        guard var annotation = selectedAnnotation, annotation.tool == .pencil else { return }
        annotation.style.lineWidth = lineWidth
        replace(annotation)
    }

    /// Cambia el número de un contador ya colocado.
    func setCounterNumber(_ number: Int, for id: UUID) {
        guard let annotation = annotations.first(where: { $0.id == id }),
              annotation.counterNumber != nil else { return }
        replace(annotation.withCounterNumber(number))
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
        pruneSelection()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(annotations)
        annotations = next
        pruneSelection()
    }

    /// Tras deshacer o rehacer, la anotación seleccionada puede haber dejado de existir.
    private func pruneSelection() {
        guard let selectedID else { return }
        if !annotations.contains(where: { $0.id == selectedID }) {
            self.selectedID = nil
        }
    }

    /// `true` cuando el documento tiene cambios sin exportar (se usa al cerrar el editor).
    var hasAnnotations: Bool { !annotations.isEmpty }
}
