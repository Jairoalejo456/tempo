import Combine
import Foundation

/// Conjunto de capturas que se editan juntas en una misma ventana.
///
/// Cada captura conserva su propio documento —sus anotaciones, su historial de deshacer y su
/// zoom—, de modo que editar varias a la vez no mezcla nada: las herramientas y la barra actúan
/// siempre sobre la que esté activa, que es la última que se ha tocado.
final class EditorStack: ObservableObject {

    @Published private(set) var documents: [EditorDocument]

    /// Documento sobre el que actúan la barra de herramientas y los atajos.
    @Published private(set) var activeID: UUID

    init(documents: [EditorDocument], activeID: UUID? = nil) {
        precondition(!documents.isEmpty, "Una pila de edición necesita al menos una captura")
        self.documents = documents
        self.activeID = activeID ?? documents[0].id
    }

    var active: EditorDocument {
        documents.first { $0.id == activeID } ?? documents[0]
    }

    /// `true` cuando hay más de una captura, que es cuando aparecen las acciones globales.
    var holdsSeveral: Bool { documents.count > 1 }

    var count: Int { documents.count }

    func document(with id: UUID) -> EditorDocument? {
        documents.first { $0.id == id }
    }

    /// Posición de una captura dentro de la pila, empezando en 1, para mostrarla al usuario.
    func position(of id: UUID) -> Int? {
        documents.firstIndex { $0.id == id }.map { $0 + 1 }
    }

    func activate(_ id: UUID) {
        guard activeID != id, documents.contains(where: { $0.id == id }) else { return }
        // Al cambiar de captura se deselecciona lo que hubiera elegido en la anterior: la barra
        // pasa a describir la nueva, y una selección invisible sería confusa.
        active.select(nil)
        activeID = id
    }

    /// Quita una captura de la pila —por ejemplo al copiarla o guardarla— y activa la siguiente.
    /// - Returns: `false` si era la última, en cuyo caso la ventana debe cerrarse.
    @discardableResult
    func remove(_ id: UUID) -> Bool {
        guard let index = documents.firstIndex(where: { $0.id == id }) else { return documents.count > 1 }
        documents.remove(at: index)
        guard !documents.isEmpty else { return false }
        if activeID == id {
            activeID = documents[min(index, documents.count - 1)].id
        }
        return true
    }

    func add(_ document: EditorDocument) {
        guard !documents.contains(where: { $0.id == document.id }) else { return }
        documents.append(document)
    }
}
