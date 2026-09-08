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
        // El blur no lleva contorno: no es un trazo, es la propia imagen difuminada.
        if case let .blur(rect) = annotation.shape {
            drawBlur(rect: rect,
                     intensity: annotation.style.blurIntensity,
                     undoingRotation: annotation.rotation == 0 ? nil : rotationTransform(for: annotation).inverted(),
                     capture: capture,
                     in: context)
            return
        }

        // Dos pasadas: primero el contorno de contraste y encima la anotación. Así se lee sobre
        // cualquier fondo, claro u oscuro, sea cual sea el color elegido.
        drawShape(annotation, in: context, asHalo: true)
        drawShape(annotation, in: context, asHalo: false)
    }

    // MARK: - Contraste

    /// Color del contorno que rodea a una anotación para separarla del fondo.
    ///
    /// Se elige por oposición a la luminancia del propio color: un trazo oscuro se rodea de
    /// claro y uno claro de oscuro. De ese modo siempre hay un salto de contraste, tanto si
    /// debajo hay una ventana blanca como una interfaz en modo oscuro.
    static func haloColor(for color: AnnotationColor) -> CGColor {
        color.isLight
            ? CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.60)
            : CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.85)
    }

    /// Cuánto sobresale el contorno por cada lado del trazo.
    static func haloWidth(for style: AnnotationStyle) -> CGFloat {
        max(1.6, style.lineWidth * 0.38)
    }

    /// Grosor total con el que se traza el contorno.
    private static func haloLineWidth(for style: AnnotationStyle) -> CGFloat {
        style.lineWidth + haloWidth(for: style) * 2
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

    // MARK: - Dibujo por herramienta

    private static func drawShape(_ annotation: Annotation, in context: CGContext, asHalo: Bool) {
        let style = annotation.style
        let color = asHalo ? haloColor(for: style.color) : style.color.cgColor
        let lineWidth = asHalo ? haloLineWidth(for: style) : style.lineWidth

        context.saveGState()
        defer { context.restoreGState() }

        switch annotation.shape {
        case let .rectangle(rect):
            context.setStrokeColor(color)
            context.setLineWidth(lineWidth)
            context.setLineJoin(.round)
            context.stroke(inset(rect, by: style.lineWidth / 2))

        case let .ellipse(rect):
            context.setStrokeColor(color)
            context.setLineWidth(lineWidth)
            context.strokeEllipse(in: inset(rect, by: style.lineWidth / 2))

        case let .arrow(from, to):
            drawArrow(from: from, to: to, style: style, color: color,
                      lineWidth: lineWidth, grow: asHalo ? haloWidth(for: style) : 0, in: context)

        case let .pencil(points):
            drawPencil(points: points, color: color, lineWidth: lineWidth, in: context)

        case let .text(origin, string):
            drawText(string, at: origin, style: style, asHalo: asHalo, in: context)

        case let .counter(center, number):
            drawCounter(number: number, center: center, style: style, asHalo: asHalo, in: context)

        case .blur:
            break // Se dibuja aparte: no lleva contorno.
        }
    }

    private static func drawBlur(rect: CGRect,
                                 intensity: CGFloat,
                                 undoingRotation inverse: CGAffineTransform?,
                                 capture: CaptureImage,
                                 in context: CGContext) {
        guard let blurred = capture.blurredImage(intensity: intensity) else { return }
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

    private static func drawArrow(from: CGPoint,
                                  to: CGPoint,
                                  style: AnnotationStyle,
                                  color: CGColor,
                                  lineWidth: CGFloat,
                                  grow: CGFloat,
                                  in context: CGContext) {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let length = hypot(dx, dy)
        guard length > 0.5 else { return }

        let angle = atan2(dy, dx)
        // La cabeza del contorno crece lo mismo que el trazo, para que el borde sea uniforme.
        let headLength = min(max(style.lineWidth * 4.2, 14) + grow * 2, length + grow * 2)
        let headWidth = max(style.lineWidth * 3.4, 11) + grow * 2

        let base = CGPoint(x: to.x - cos(angle) * headLength,
                           y: to.y - sin(angle) * headLength)
        let tip = CGPoint(x: to.x + cos(angle) * grow, y: to.y + sin(angle) * grow)
        let perpendicular = CGPoint(x: -sin(angle) * headWidth / 2, y: cos(angle) * headWidth / 2)

        context.setFillColor(color)
        context.setStrokeColor(color)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)

        // Cuerpo: termina dentro de la cabeza para que no asome por los lados.
        if length > headLength * 0.9 {
            context.beginPath()
            context.move(to: from)
            context.addLine(to: CGPoint(x: to.x - cos(angle) * headLength * 0.75,
                                        y: to.y - sin(angle) * headLength * 0.75))
            context.strokePath()
        }

        context.beginPath()
        context.move(to: tip)
        context.addLine(to: CGPoint(x: base.x + perpendicular.x, y: base.y + perpendicular.y))
        context.addLine(to: CGPoint(x: base.x - perpendicular.x, y: base.y - perpendicular.y))
        context.closePath()
        context.fillPath()
    }

    private static func drawPencil(points: [CGPoint], color: CGColor, lineWidth: CGFloat, in context: CGContext) {
        guard points.count > 1 else {
            if let single = points.first {
                context.setFillColor(color)
                context.fillEllipse(in: CGRect(x: single.x - lineWidth / 2,
                                               y: single.y - lineWidth / 2,
                                               width: lineWidth,
                                               height: lineWidth))
            }
            return
        }

        context.setStrokeColor(color)
        context.setLineWidth(lineWidth)
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

    private static func drawText(_ string: String,
                                 at origin: CGPoint,
                                 style: AnnotationStyle,
                                 asHalo: Bool,
                                 in context: CGContext) {
        guard !string.isEmpty else { return }

        var attributes = textAttributes(style: style)
        if asHalo {
            // `strokeWidth` positivo traza sólo el contorno de las letras, sin rellenarlas: el
            // relleno lo pone la segunda pasada. Va en porcentaje del cuerpo de letra, así que
            // el contorno crece con el tamaño del texto.
            attributes[.strokeWidth] = 9.0
            attributes[.strokeColor] = NSColor(cgColor: haloColor(for: style.color)) ?? .black
        }

        let attributed = NSAttributedString(string: string, attributes: attributes)
        withAppKitContext(context) {
            // `origin` es la esquina inferior izquierda del bloque de texto.
            attributed.draw(at: origin)
        }
    }

    private static func drawCounter(number: Int,
                                    center: CGPoint,
                                    style: AnnotationStyle,
                                    asHalo: Bool,
                                    in context: CGContext) {
        let radius = counterRadius(for: style)

        if asHalo {
            // Un anillo alrededor del círculo: lo despega de fondos del mismo tono.
            let grown = radius + haloWidth(for: style)
            context.setFillColor(haloColor(for: style.color))
            context.fillEllipse(in: CGRect(x: center.x - grown, y: center.y - grown,
                                           width: grown * 2, height: grown * 2))
            return
        }

        context.setFillColor(style.color.cgColor)
        context.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                       width: radius * 2, height: radius * 2))

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
