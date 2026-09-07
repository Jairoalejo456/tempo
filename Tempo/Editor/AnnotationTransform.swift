import CoreGraphics
import Foundation

/// Transformaciones de una anotación ya creada: desplazarla, cambiarle el tamaño y girarla.
///
/// Todas devuelven una copia; el documento decide cuándo el cambio entra en el historial, de
/// modo que un arrastre completo cuenta como una sola operación de deshacer.
extension Annotation {

    // MARK: - Desplazar

    func moved(by delta: CGSize) -> Annotation {
        var copy = self
        copy.shape = shape.moved(by: delta)
        return copy
    }

    // MARK: - Cambiar de tamaño

    /// Aplica el arrastre de un tirador. `point` va en coordenadas de imagen.
    /// - Parameter keepingAspect: mantiene la proporción (tecla Mayúsculas).
    func resized(handle: AnnotationHandle, to point: CGPoint, keepingAspect: Bool = false) -> Annotation {
        // Los extremos de una flecha se mueven tal cual, sin pasar por la caja.
        if case let .arrow(from, to) = shape {
            var copy = self
            switch handle {
            case .start: copy.shape = .arrow(from: toLocal(point), to: to)
            case .end: copy.shape = .arrow(from: from, to: toLocal(point))
            default: break
            }
            return copy
        }

        let local = toLocal(point)
        let bounds = localBounds
        var rect = bounds

        switch handle {
        case .topLeft:
            rect = CGRect(x: min(local.x, bounds.maxX), y: min(local.y, bounds.maxY),
                          width: abs(bounds.maxX - local.x), height: abs(local.y - bounds.minY))
            rect.origin.y = bounds.minY
            rect.size.height = max(local.y - bounds.minY, 1)
            rect.origin.x = min(local.x, bounds.maxX - 1)
            rect.size.width = max(bounds.maxX - local.x, 1)
        case .topRight:
            rect.origin.y = bounds.minY
            rect.size.height = max(local.y - bounds.minY, 1)
            rect.size.width = max(local.x - bounds.minX, 1)
        case .bottomLeft:
            rect.origin.x = min(local.x, bounds.maxX - 1)
            rect.size.width = max(bounds.maxX - local.x, 1)
            rect.origin.y = min(local.y, bounds.maxY - 1)
            rect.size.height = max(bounds.maxY - local.y, 1)
        case .bottomRight:
            rect.size.width = max(local.x - bounds.minX, 1)
            rect.origin.y = min(local.y, bounds.maxY - 1)
            rect.size.height = max(bounds.maxY - local.y, 1)
        case .top:
            rect.size.height = max(local.y - bounds.minY, 1)
        case .bottom:
            rect.origin.y = min(local.y, bounds.maxY - 1)
            rect.size.height = max(bounds.maxY - local.y, 1)
        case .left:
            rect.origin.x = min(local.x, bounds.maxX - 1)
            rect.size.width = max(bounds.maxX - local.x, 1)
        case .right:
            rect.size.width = max(local.x - bounds.minX, 1)
        case .start, .end, .rotate:
            return self
        }

        if keepingAspect, bounds.width > 0, bounds.height > 0 {
            let ratio = bounds.height / bounds.width
            rect.size.height = max(rect.size.width * ratio, 1)
        }

        return withBounds(rect, from: bounds)
    }

    /// Reconstruye la forma para que ocupe `rect`, partiendo de `previous`.
    private func withBounds(_ rect: CGRect, from previous: CGRect) -> Annotation {
        var copy = self
        switch shape {
        case .rectangle:
            copy.shape = .rectangle(rect)
        case .ellipse:
            copy.shape = .ellipse(rect)
        case .blur:
            copy.shape = .blur(rect)
        case let .pencil(points):
            // El trazo se escala punto a punto dentro de la nueva caja.
            guard previous.width > 0, previous.height > 0 else { return self }
            let scaleX = rect.width / previous.width
            let scaleY = rect.height / previous.height
            copy.shape = .pencil(points: points.map { point in
                CGPoint(x: rect.minX + (point.x - previous.minX) * scaleX,
                        y: rect.minY + (point.y - previous.minY) * scaleY)
            })
        case let .text(_, string):
            // En un texto, cambiar el tamaño de la caja cambia el cuerpo de letra.
            guard previous.height > 0 else { return self }
            let factor = rect.height / previous.height
            copy.style.fontSize = min(max(style.fontSize * factor, 8), 400)
            let newSize = AnnotationRenderer.textSize(string, style: copy.style)
            copy.shape = .text(origin: CGPoint(x: rect.minX, y: rect.minY), string: string)
            _ = newSize
        case let .counter(_, number):
            let side = max(min(rect.width, rect.height), 8)
            copy.style.fontSize = min(max(side / 2 / 0.72, 8), 400)
            let radius = AnnotationRenderer.counterRadius(for: copy.style)
            copy.shape = .counter(center: CGPoint(x: rect.minX + radius, y: rect.maxY - radius),
                                  number: number)
        case .arrow:
            break
        }
        return copy
    }

    // MARK: - Girar

    /// Gira la anotación de modo que el tirador de giro quede bajo `point`.
    /// - Parameter snapping: ajusta a múltiplos de 15° (tecla Mayúsculas).
    func rotated(towards point: CGPoint, snapping: Bool = false) -> Annotation {
        guard canRotate else { return self }
        let pivot = center
        // El tirador nace mirando hacia arriba, así que se resta esa referencia.
        var angle = atan2(point.y - pivot.y, point.x - pivot.x) - .pi / 2
        if snapping {
            let step = CGFloat.pi / 12 // 15°
            angle = (angle / step).rounded() * step
        }
        var copy = self
        copy.rotation = angle
        return copy
    }

    // MARK: - Contadores

    /// Devuelve una copia con otro número. Permite renumerar a mano un contador ya puesto.
    func withCounterNumber(_ number: Int) -> Annotation {
        guard case let .counter(center, _) = shape else { return self }
        var copy = self
        copy.shape = .counter(center: center, number: max(0, min(number, 9999)))
        return copy
    }

    var counterNumber: Int? {
        if case let .counter(_, number) = shape { return number }
        return nil
    }

    var textContent: String? {
        if case let .text(_, string) = shape { return string }
        return nil
    }

    func withText(_ string: String) -> Annotation {
        guard case let .text(origin, _) = shape else { return self }
        var copy = self
        copy.shape = .text(origin: origin, string: string)
        return copy
    }
}

extension AnnotationShape {
    /// Desplaza la forma completa.
    func moved(by delta: CGSize) -> AnnotationShape {
        func move(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x + delta.width, y: point.y + delta.height)
        }
        switch self {
        case let .arrow(from, to):
            return .arrow(from: move(from), to: move(to))
        case let .rectangle(rect):
            return .rectangle(rect.offsetBy(dx: delta.width, dy: delta.height))
        case let .ellipse(rect):
            return .ellipse(rect.offsetBy(dx: delta.width, dy: delta.height))
        case let .blur(rect):
            return .blur(rect.offsetBy(dx: delta.width, dy: delta.height))
        case let .pencil(points):
            return .pencil(points: points.map(move))
        case let .text(origin, string):
            return .text(origin: move(origin), string: string)
        case let .counter(center, number):
            return .counter(center: move(center), number: number)
        }
    }
}
