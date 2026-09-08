import Foundation

/// Herramienta activa en el editor.
///
/// La navegación no es una anotación —no pinta nada— pero sí es un modo del editor, así que se
/// modela aparte de `AnnotationTool` para que el compilador impida crear una "anotación de
/// puntero" por descuido.
enum EditorTool: Equatable, Hashable, Identifiable {
    /// Puntero: desplazar la captura arrastrando y hacer zoom con la rueda.
    case navigate
    /// Ajustar el encuadre de la captura.
    case crop
    /// Cualquiera de las herramientas de dibujo.
    case annotate(AnnotationTool)

    var id: String {
        switch self {
        case .navigate: return "navigate"
        case .crop: return "crop"
        case let .annotate(tool): return tool.rawValue
        }
    }

    /// Herramienta de dibujo asociada, si la hay.
    var annotationTool: AnnotationTool? {
        switch self {
        case .navigate, .crop: return nil
        case let .annotate(tool): return tool
        }
    }

    var title: String {
        switch self {
        case .navigate: return "Puntero"
        case .crop: return "Recortar"
        case let .annotate(tool): return tool.title
        }
    }

    var symbolName: String {
        switch self {
        case .navigate: return "cursorarrow"
        case .crop: return "crop"
        case let .annotate(tool): return tool.symbolName
        }
    }

    var shortcutKey: String {
        switch self {
        case .navigate: return "v"
        case .crop: return "k"
        case let .annotate(tool): return tool.shortcutKey
        }
    }

    /// Si la paleta de colores es relevante con esta herramienta.
    ///
    /// Con el puntero lo es: elegir un color mientras se navega deja preparado el que usará la
    /// siguiente anotación. No lo es con el blur, que no pinta con color, ni con el recorte,
    /// que no pinta nada en absoluto.
    var usesColor: Bool {
        switch self {
        case .navigate: return true
        case .crop: return false
        case let .annotate(tool): return tool.usesColor
        }
    }

    /// Orden en que se muestran en la barra de herramientas.
    static var allCases: [EditorTool] {
        [.navigate] + AnnotationTool.allCases.map(EditorTool.annotate) + [.crop]
    }
}
