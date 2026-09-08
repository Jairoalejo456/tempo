import CoreGraphics

extension CGRect {
    /// Rectángulo comprendido entre dos puntos, sea cual sea el orden en que se den.
    ///
    /// Lo usan todos los gestos que se dibujan arrastrando —la selección de región, las formas
    /// del editor y el encuadre del recorte—, para que todos funcionen igual en las cuatro
    /// direcciones. Construirlo a mano en cada sitio es justo lo que hacía que alguno sólo
    /// creciera hacia un lado.
    static func between(_ first: CGPoint, _ second: CGPoint) -> CGRect {
        CGRect(x: min(first.x, second.x),
               y: min(first.y, second.y),
               width: abs(second.x - first.x),
               height: abs(second.y - first.y))
    }
}
