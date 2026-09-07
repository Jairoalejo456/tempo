import AppKit
import CoreGraphics
import Foundation

/// Tirador de manipulación de una anotación seleccionada.
enum AnnotationHandle: Hashable, CaseIterable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
    /// Extremos de una flecha: moverlos cambia su longitud y su orientación.
    case start, end
    /// Tirador de giro, por encima del borde superior.
    case rotate

    /// Tiradores de una caja rectangular, en orden.
    static let boxHandles: [AnnotationHandle] = [
        .topLeft, .top, .topRight, .right, .bottomRight, .bottom, .bottomLeft, .left
    ]

    var cursor: NSCursor {
        switch self {
        case .rotate: return .crosshair
        default: return .crosshair
        }
    }
}

/// Geometría de las anotaciones: dónde están, qué se pulsó y cómo se transforman.
///
/// Todo se calcula en coordenadas de la imagen. La rotación se trata de forma uniforme: la
/// forma se define siempre sin girar y el giro se aplica alrededor del centro de su caja, tanto
/// al dibujar como al buscar el punto pulsado.
extension Annotation {

    // MARK: - Cajas

    /// Caja que ocupa la anotación **sin** aplicar su giro.
    var localBounds: CGRect {
        switch shape {
        case let .rectangle(rect), let .ellipse(rect), let .blur(rect):
            return rect
        case let .arrow(from, to):
            let rect = CGRect(x: min(from.x, to.x), y: min(from.y, to.y),
                              width: abs(to.x - from.x), height: abs(to.y - from.y))
            return rect.insetBy(dx: -style.lineWidth, dy: -style.lineWidth)
        case let .pencil(points):
            guard let first = points.first else { return .zero }
            var rect = CGRect(origin: first, size: .zero)
            for point in points.dropFirst() {
                rect = rect.union(CGRect(origin: point, size: .zero))
            }
            return rect.insetBy(dx: -style.lineWidth, dy: -style.lineWidth)
        case let .text(origin, string):
            let size = AnnotationRenderer.textSize(string, style: style)
            return CGRect(origin: origin, size: size)
        case let .counter(center, _):
            let radius = AnnotationRenderer.counterRadius(for: style)
            return CGRect(x: center.x - radius, y: center.y - radius,
                          width: radius * 2, height: radius * 2)
        }
    }

    var center: CGPoint {
        let bounds = localBounds
        return CGPoint(x: bounds.midX, y: bounds.midY)
    }

    /// Convierte un punto del espacio de la imagen al espacio sin girar de la anotación.
    func toLocal(_ point: CGPoint) -> CGPoint {
        guard rotation != 0 else { return point }
        return rotate(point, around: center, by: -rotation)
    }

    /// Convierte un punto del espacio de la anotación al espacio de la imagen.
    func toImage(_ point: CGPoint) -> CGPoint {
        guard rotation != 0 else { return point }
        return rotate(point, around: center, by: rotation)
    }

    private func rotate(_ point: CGPoint, around pivot: CGPoint, by angle: CGFloat) -> CGPoint {
        let dx = point.x - pivot.x
        let dy = point.y - pivot.y
        let cosine = cos(angle), sine = sin(angle)
        return CGPoint(x: pivot.x + dx * cosine - dy * sine,
                       y: pivot.y + dx * sine + dy * cosine)
    }

    // MARK: - ¿Se pulsó encima?

    /// `true` si el punto dado (en coordenadas de imagen) toca la anotación.
    func hitTest(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        let local = toLocal(point)
        let margin = max(tolerance, style.lineWidth)

        switch shape {
        case let .rectangle(rect), let .ellipse(rect):
            // Las formas sin relleno se agarran por su contorno, para poder seleccionar
            // lo que haya dentro de un rectángulo grande.
            let outer = rect.insetBy(dx: -margin, dy: -margin)
            let inner = rect.insetBy(dx: margin, dy: margin)
            return outer.contains(local) && !inner.contains(local)
        case let .blur(rect):
            // El blur sí está relleno: se agarra por cualquier punto.
            return rect.insetBy(dx: -margin, dy: -margin).contains(local)
        case let .arrow(from, to):
            return distance(from: local, toSegment: from, end: to) <= margin
        case let .pencil(points):
            guard points.count > 1 else { return false }
            for index in 0..<(points.count - 1) {
                if distance(from: local, toSegment: points[index], end: points[index + 1]) <= margin {
                    return true
                }
            }
            return false
        case .text:
            return localBounds.insetBy(dx: -margin / 2, dy: -margin / 2).contains(local)
        case let .counter(center, _):
            let radius = AnnotationRenderer.counterRadius(for: style) + margin / 2
            return hypot(local.x - center.x, local.y - center.y) <= radius
        }
    }

    private func distance(from point: CGPoint, toSegment start: CGPoint, end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(point.x - start.x, point.y - start.y) }
        var t = ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared
        t = min(max(t, 0), 1)
        let projection = CGPoint(x: start.x + t * dx, y: start.y + t * dy)
        return hypot(point.x - projection.x, point.y - projection.y)
    }

    // MARK: - Tiradores

    /// Tiradores disponibles y su posición en coordenadas de imagen (ya girados).
    func handlePositions() -> [AnnotationHandle: CGPoint] {
        var result: [AnnotationHandle: CGPoint] = [:]

        if case let .arrow(from, to) = shape {
            // Una flecha se manipula por sus extremos: eso cubre longitud y orientación.
            result[.start] = toImage(from)
            result[.end] = toImage(to)
            return result
        }

        let bounds = localBounds
        let positions: [AnnotationHandle: CGPoint] = [
            .topLeft: CGPoint(x: bounds.minX, y: bounds.maxY),
            .top: CGPoint(x: bounds.midX, y: bounds.maxY),
            .topRight: CGPoint(x: bounds.maxX, y: bounds.maxY),
            .right: CGPoint(x: bounds.maxX, y: bounds.midY),
            .bottomRight: CGPoint(x: bounds.maxX, y: bounds.minY),
            .bottom: CGPoint(x: bounds.midX, y: bounds.minY),
            .bottomLeft: CGPoint(x: bounds.minX, y: bounds.minY),
            .left: CGPoint(x: bounds.minX, y: bounds.midY)
        ]

        switch shape {
        case .counter:
            // Un contador es un círculo: basta con las esquinas para cambiar su tamaño.
            for handle in [AnnotationHandle.topLeft, .topRight, .bottomRight, .bottomLeft] {
                result[handle] = toImage(positions[handle]!)
            }
        case .text:
            for handle in [AnnotationHandle.topRight, .bottomRight, .bottomLeft, .topLeft] {
                result[handle] = toImage(positions[handle]!)
            }
        default:
            for (handle, point) in positions {
                result[handle] = toImage(point)
            }
        }

        // El giro no se ofrece donde no aporta nada.
        if canRotate {
            result[.rotate] = toImage(CGPoint(x: bounds.midX, y: bounds.maxY + rotateHandleOffset))
        }
        return result
    }

    /// Distancia del tirador de giro respecto al borde superior.
    var rotateHandleOffset: CGFloat { 26 }

    /// Girar un contador no tendría ningún efecto visible, y una flecha ya se reorienta
    /// moviendo sus extremos.
    var canRotate: Bool {
        switch shape {
        case .counter, .arrow: return false
        default: return true
        }
    }

    /// Tirador que se encuentra bajo el punto indicado, si hay alguno.
    func handle(at point: CGPoint, tolerance: CGFloat) -> AnnotationHandle? {
        handlePositions()
            .filter { hypot(point.x - $0.value.x, point.y - $0.value.y) <= tolerance }
            .min { first, second in
                hypot(point.x - first.value.x, point.y - first.value.y)
                    < hypot(point.x - second.value.x, point.y - second.value.y)
            }?.key
    }
}
