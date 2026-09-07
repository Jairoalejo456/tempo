import AppKit
import CoreGraphics
import Foundation

/// Dibuja la captura y sus anotaciones en un `CGContext`.
///
/// Es el único punto donde se define el aspecto de cada herramienta: lo usa tanto el lienzo
/// del editor como el exportador, de forma que lo que se ve en pantalla es exactamente lo que
/// se copia al portapapeles o se guarda en disco.
///
/// El contexto recibido debe estar en **coordenadas lógicas** (origen abajo‑izquierda, unidades
/// en puntos), es decir, ya escalado por el factor Retina si se está exportando a píxeles.
enum AnnotationRenderer {

    // MARK: - API

    static func drawBase(_ capture: CaptureImage, in context: CGContext) {
        context.saveGState()
        context.interpolationQuality = .high
        context.draw(capture.cgImage, in: capture.logicalBounds)
        context.restoreGState()
    }

    static func draw(_ annotations: [Annotation], capture: CaptureImage, in context: CGContext) {
        for annotation in annotations {
            draw(annotation, capture: capture, in: context)
        }
    }

    static func draw(_ annotation: Annotation, capture: CaptureImage, in context: CGContext) {
        guard annotation.rotation != 0 else {
            drawUnrotated(annotation, capture: capture, in: context)
            return
        }
        context.saveGState()
        context.concatenate(rotationTransform(for: annotation))
        drawUnrotated(annotation, capture: capture, in: context)
        context.restoreGState()
    }

    /// Giro alrededor del centro de la anotación.
    static func rotationTransform(for annotation: Annotation) -> CGAffineTransform {
        let pivot = annotation.center
        return CGAffineTransform(translationX: pivot.x, y: pivot.y)
            .rotated(by: annotation.rotation)
            .translatedBy(x: -pivot.x, y: -pivot.y)
    }

    private static func drawUnrotated(_ annotation: Annotation, capture: CaptureImage, in context: CGContext) {
        switch annotation.shape {
        case let .blur(rect):
            drawBlur(rect: rect,
                     undoingRotation: annotation.rotation == 0 ? nil : rotationTransform(for: annotation).inverted(),
                     capture: capture,
                     in: context)
        case let .rectangle(rect):
            withShadow(in: context) {
                context.setStrokeColor(annotation.style.color.cgColor)
                context.setLineWidth(annotation.style.lineWidth)
                context.setLineJoin(.round)
                context.stroke(inset(rect, by: annotation.style.lineWidth / 2))
            }
        case let .ellipse(rect):
            withShadow(in: context) {
                context.setStrokeColor(annotation.style.color.cgColor)
                context.setLineWidth(annotation.style.lineWidth)
                context.strokeEllipse(in: inset(rect, by: annotation.style.lineWidth / 2))
            }
        case let .arrow(from, to):
            withShadow(in: context) {
                drawArrow(from: from, to: to, style: annotation.style, in: context)
            }
        case let .pencil(points):
            withShadow(in: context) {
                drawPencil(points: points, style: annotation.style, in: context)
            }
        case let .text(origin, string):
            withShadow(in: context) {
                drawText(string, at: origin, style: annotation.style, in: context)
            }
        case let .counter(center, number):
            withShadow(in: context) {
                drawCounter(number: number, center: center, style: annotation.style, in: context)
            }
        }
    }

    // MARK: - Métricas compartidas con la interfaz

    /// Radio del círculo de un contador para un tamaño de fuente dado.
    static func counterRadius(for style: AnnotationStyle) -> CGFloat {
        max(14, style.fontSize * 0.72)
    }

    /// Tamaño que ocupará un texto; lo usa el editor para colocar el campo de edición.
    static func textSize(_ string: String, style: AnnotationStyle) -> CGSize {
        guard !string.isEmpty else { return CGSize(width: 0, height: style.fontSize * 1.25) }
        return NSAttributedString(string: string, attributes: textAttributes(style: style)).size()
    }

    // MARK: - Implementación por herramienta

    private static func drawBlur(rect: CGRect,
                                 undoingRotation inverse: CGAffineTransform?,
                                 capture: CaptureImage,
                                 in context: CGContext) {
        guard let blurred = capture.blurredImage() else { return }
        context.saveGState()
        // El recorte sí gira con el rectángulo…
        context.clip(to: rect)
        // …pero la imagen difuminada debe quedar alineada con la captura: si girase, el
        // difuminado dejaría de corresponderse con lo que hay debajo. Se deshace aquí el giro
        // que ya aplicó quien nos llamó.
        if let inverse {
            context.concatenate(inverse)
        }
        context.interpolationQuality = .high
        context.draw(blurred, in: capture.logicalBounds)
        context.restoreGState()
    }

    private static func drawArrow(from: CGPoint, to: CGPoint, style: AnnotationStyle, in context: CGContext) {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let length = hypot(dx, dy)
        guard length > 0.5 else { return }

        let angle = atan2(dy, dx)
        let headLength = min(max(style.lineWidth * 4.2, 14), length)
        let headWidth = max(style.lineWidth * 3.4, 11)

        let base = CGPoint(x: to.x - cos(angle) * headLength,
                           y: to.y - sin(angle) * headLength)
        let perpendicular = CGPoint(x: -sin(angle) * headWidth / 2, y: cos(angle) * headWidth / 2)

        context.setFillColor(style.color.cgColor)
        context.setStrokeColor(style.color.cgColor)
        context.setLineWidth(style.lineWidth)
        context.setLineCap(.round)

        // Cuerpo: termina dentro de la cabeza para que no asome por los lados.
        if length > headLength * 0.9 {
            context.beginPath()
            context.move(to: from)
            context.addLine(to: CGPoint(x: to.x - cos(angle) * headLength * 0.75,
                                        y: to.y - sin(angle) * headLength * 0.75))
            context.strokePath()
        }

        // Cabeza.
        context.beginPath()
        context.move(to: to)
        context.addLine(to: CGPoint(x: base.x + perpendicular.x, y: base.y + perpendicular.y))
        context.addLine(to: CGPoint(x: base.x - perpendicular.x, y: base.y - perpendicular.y))
        context.closePath()
        context.fillPath()
    }

    private static func drawPencil(points: [CGPoint], style: AnnotationStyle, in context: CGContext) {
        guard points.count > 1 else {
            if let single = points.first {
                context.setFillColor(style.color.cgColor)
                context.fillEllipse(in: CGRect(x: single.x - style.lineWidth / 2,
                                               y: single.y - style.lineWidth / 2,
                                               width: style.lineWidth,
                                               height: style.lineWidth))
            }
            return
        }

        context.setStrokeColor(style.color.cgColor)
        context.setLineWidth(style.lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.beginPath()
        context.move(to: points[0])

        if points.count == 2 {
            context.addLine(to: points[1])
        } else {
            // Suavizado: curvas cuadráticas entre los puntos medios de cada par consecutivo.
            for index in 1..<(points.count - 1) {
                let current = points[index]
                let next = points[index + 1]
                let mid = CGPoint(x: (current.x + next.x) / 2, y: (current.y + next.y) / 2)
                context.addQuadCurve(to: mid, control: current)
            }
            context.addLine(to: points[points.count - 1])
        }
        context.strokePath()
    }

    private static func drawText(_ string: String, at origin: CGPoint, style: AnnotationStyle, in context: CGContext) {
        guard !string.isEmpty else { return }
        let attributed = NSAttributedString(string: string, attributes: textAttributes(style: style))
        withAppKitContext(context) {
            // `origin` es la esquina inferior izquierda del bloque de texto.
            attributed.draw(at: origin)
        }
    }

    private static func drawCounter(number: Int, center: CGPoint, style: AnnotationStyle, in context: CGContext) {
        let radius = counterRadius(for: style)
        let circle = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)

        context.setFillColor(style.color.cgColor)
        context.fillEllipse(in: circle)

        let numberColor: NSColor = style.color.isLight ? NSColor(white: 0.1, alpha: 1) : .white
        let font = NSFont.systemFont(ofSize: radius * 1.15, weight: .bold)
        let attributed = NSAttributedString(string: "\(number)", attributes: [
            .font: font,
            .foregroundColor: numberColor
        ])
        let size = attributed.size()
        let point = CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)
        withAppKitContext(context) {
            attributed.draw(at: point)
        }
    }

    // MARK: - Utilidades

    private static func textAttributes(style: AnnotationStyle) -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: style.fontSize, weight: .semibold),
            .foregroundColor: NSColor(cgColor: style.color.cgColor) ?? .systemRed
        ]
    }

    /// Sombra discreta para que cualquier anotación mantenga contraste sobre fondos claros y oscuros.
    private static func withShadow(in context: CGContext, _ body: () -> Void) {
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -1),
                          blur: 3,
                          color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.35))
        body()
        context.restoreGState()
    }

    /// Permite dibujar texto de AppKit dentro de un `CGContext` arbitrario (pantalla o bitmap).
    private static func withAppKitContext(_ context: CGContext, _ body: () -> Void) {
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        body()
        NSGraphicsContext.current = previous
    }

    private static func inset(_ rect: CGRect, by amount: CGFloat) -> CGRect {
        guard rect.width > amount * 2, rect.height > amount * 2 else { return rect }
        return rect.insetBy(dx: amount, dy: amount)
    }
}
