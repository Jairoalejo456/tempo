import CoreGraphics
import Foundation

/// Herramientas del editor. El `rawValue` se usa en la interfaz y en las pruebas.
enum AnnotationTool: String, CaseIterable, Identifiable {
    case arrow
    case rectangle
    case ellipse
    case text
    case pencil
    case blur
    case counter

    var id: String { rawValue }

    /// Nombre visible en la interfaz.
    var title: String {
        switch self {
        case .arrow: return "Flecha"
        case .rectangle: return "Rectángulo"
        case .ellipse: return "Elipse"
        case .text: return "Texto"
        case .pencil: return "Lápiz"
        case .blur: return "Blur"
        case .counter: return "Contador"
        }
    }

    /// SF Symbol usado en la barra de herramientas.
    var symbolName: String {
        switch self {
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .text: return "textformat"
        case .pencil: return "pencil.tip"
        case .blur: return "drop.halffull"
        case .counter: return "1.circle"
        }
    }

    /// Tecla única (sin modificadores) que activa la herramienta.
    var shortcutKey: String {
        switch self {
        case .arrow: return "a"
        case .rectangle: return "r"
        case .ellipse: return "o"
        case .text: return "t"
        case .pencil: return "p"
        case .blur: return "b"
        case .counter: return "c"
        }
    }

    /// Indica si la herramienta usa el color activo.
    var usesColor: Bool { self != .blur }
}

/// Geometría de una anotación, en coordenadas lógicas de la imagen (origen abajo‑izquierda,
/// las mismas que usa Core Graphics, de modo que dibujar en pantalla y exportar son idénticos).
enum AnnotationShape: Equatable {
    case arrow(from: CGPoint, to: CGPoint)
    case rectangle(CGRect)
    case ellipse(CGRect)
    case pencil(points: [CGPoint])
    case blur(CGRect)
    case text(origin: CGPoint, string: String)
    case counter(center: CGPoint, number: Int)

    var tool: AnnotationTool {
        switch self {
        case .arrow: return .arrow
        case .rectangle: return .rectangle
        case .ellipse: return .ellipse
        case .pencil: return .pencil
        case .blur: return .blur
        case .text: return .text
        case .counter: return .counter
        }
    }
}

/// Estilo con el que se dibuja una anotación.
struct AnnotationStyle: Equatable {
    var color: AnnotationColor
    var lineWidth: CGFloat
    var fontSize: CGFloat

    static let `default` = AnnotationStyle(color: .red, lineWidth: 4, fontSize: 28)
}

struct Annotation: Identifiable, Equatable {
    let id: UUID
    var shape: AnnotationShape
    var style: AnnotationStyle
    /// Giro en radianes alrededor del centro de la anotación. Se guarda aparte de la forma
    /// para que la geometría siga siendo sencilla: la forma vive sin rotar y el giro se aplica
    /// al dibujar, al buscar el punto pulsado y al colocar los tiradores.
    var rotation: CGFloat

    init(id: UUID = UUID(), shape: AnnotationShape, style: AnnotationStyle, rotation: CGFloat = 0) {
        self.id = id
        self.shape = shape
        self.style = style
        self.rotation = rotation
    }

    var tool: AnnotationTool { shape.tool }

    /// Una anotación es descartable cuando el gesto que la creó no produjo nada visible
    /// (por ejemplo un clic sin arrastre con la herramienta rectángulo, o un texto vacío).
    var isMeaningful: Bool {
        switch shape {
        case let .arrow(from, to):
            return hypot(to.x - from.x, to.y - from.y) >= 4
        case let .rectangle(rect), let .ellipse(rect), let .blur(rect):
            return rect.width >= 3 && rect.height >= 3
        case let .pencil(points):
            return points.count >= 2
        case let .text(_, string):
            return !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .counter:
            return true
        }
    }
}
