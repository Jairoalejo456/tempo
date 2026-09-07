import CoreGraphics
import Foundation

/// Color independiente de AppKit para que el modelo sea puro, comparable y serializable.
struct AnnotationColor: Equatable, Hashable, Codable {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
    var alpha: CGFloat

    init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    func withAlpha(_ value: CGFloat) -> AnnotationColor {
        AnnotationColor(red: red, green: green, blue: blue, alpha: value)
    }

    /// Luminancia relativa aproximada; sirve para elegir el color del número de un contador.
    var isLight: Bool {
        (0.299 * red + 0.587 * green + 0.114 * blue) > 0.65
    }
}

extension AnnotationColor {
    static let red = AnnotationColor(red: 1.00, green: 0.23, blue: 0.19)
    static let orange = AnnotationColor(red: 1.00, green: 0.58, blue: 0.00)
    static let yellow = AnnotationColor(red: 1.00, green: 0.84, blue: 0.04)
    static let green = AnnotationColor(red: 0.20, green: 0.78, blue: 0.35)
    static let blue = AnnotationColor(red: 0.04, green: 0.52, blue: 1.00)
    static let purple = AnnotationColor(red: 0.69, green: 0.32, blue: 0.87)
    static let white = AnnotationColor(red: 1, green: 1, blue: 1)
    static let black = AnnotationColor(red: 0.11, green: 0.11, blue: 0.12)

    /// Paleta de la barra de herramientas, en el orden en que se muestra (teclas 1…8).
    static let palette: [AnnotationColor] = [.red, .orange, .yellow, .green, .blue, .purple, .white, .black]
}
