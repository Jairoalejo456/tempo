import AppKit
import CoreGraphics
import Foundation

/// Genera una imagen de muestra con todas las herramientas aplicadas sobre un lienzo sintético.
///
/// Se ejecuta con `Tempo.app --render-sample <ruta.png>`. Sirve para revisar de un vistazo
/// cómo se dibuja cada herramienta sin necesidad de hacer una captura real, y usa exactamente
/// el mismo renderizador que el editor.
enum SampleRenderer {

    static func run(outputPath: String) -> Never {
        let capture = makeSyntheticCapture()
        let document = EditorDocument(capture: capture)
        addSampleAnnotations(to: document)

        do {
            let image = try ImageExporter.compose(document: document)
            let url = URL(fileURLWithPath: (outputPath as NSString).expandingTildeInPath)
            try ImageExporter.write(image: image, to: url)
            print("Muestra escrita en \(url.path) (\(image.width)×\(image.height) px)")
            exit(0)
        } catch {
            print("No se pudo generar la muestra: \(error.localizedDescription)")
            exit(1)
        }
    }

    /// Comprobación de contraste: las mismas anotaciones, en todos los colores, sobre fondos
    /// claros, oscuros y de tonos intermedios. Sirve para verificar que se leen en cualquier
    /// caso, que es lo que justifica el contorno de contraste del renderizador.
    static func runContrastCheck(outputPath: String) -> Never {
        let capture = makeContrastCanvas()
        let document = EditorDocument(capture: capture)
        let size = capture.logicalSize
        let columnWidth = size.width / CGFloat(AnnotationColor.palette.count)

        for (index, color) in AnnotationColor.palette.enumerated() {
            document.color = color
            let x = columnWidth * CGFloat(index) + columnWidth / 2

            document.add(Annotation(shape: .text(origin: CGPoint(x: x - 26, y: size.height - 70),
                                                 string: "Abc"),
                                    style: AnnotationStyle(color: color, lineWidth: 4, fontSize: 30)))
            document.add(Annotation(shape: .arrow(from: CGPoint(x: x - 30, y: size.height - 150),
                                                  to: CGPoint(x: x + 30, y: size.height - 110)),
                                    style: AnnotationStyle(color: color, lineWidth: 4, fontSize: 28)))
            document.add(Annotation(shape: .rectangle(CGRect(x: x - 34, y: size.height - 250,
                                                             width: 68, height: 60)),
                                    style: AnnotationStyle(color: color, lineWidth: 4, fontSize: 28)))
            document.add(Annotation(shape: .counter(center: CGPoint(x: x, y: size.height - 300),
                                                    number: index + 1),
                                    style: AnnotationStyle(color: color, lineWidth: 4, fontSize: 24)))
            document.add(Annotation(shape: .pencil(points: (0..<16).map {
                CGPoint(x: x - 32 + Double($0) * 4, y: size.height - 370 + sin(Double($0) / 2) * 14)
            }), style: AnnotationStyle(color: color, lineWidth: 4, fontSize: 28)))
        }
        document.select(nil)

        do {
            let image = try ImageExporter.compose(document: document)
            let url = URL(fileURLWithPath: (outputPath as NSString).expandingTildeInPath)
            try ImageExporter.write(image: image, to: url)
            print("Comprobación de contraste en \(url.path) (\(image.width)×\(image.height) px)")
            exit(0)
        } catch {
            print("No se pudo generar: \(error.localizedDescription)")
            exit(1)
        }
    }

    /// Bandas horizontales que van del blanco al negro, para probar el peor caso de cada color.
    private static func makeContrastCanvas(scale: CGFloat = 2) -> CaptureImage {
        let width: CGFloat = 760, height: CGFloat = 420
        let context = CGContext(data: nil,
                                width: Int(width * scale), height: Int(height * scale),
                                bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: scale, y: scale)

        let tones: [CGFloat] = [1.0, 0.75, 0.45, 0.16, 0.0]
        let bandHeight = height / CGFloat(tones.count)
        for (index, tone) in tones.enumerated() {
            context.setFillColor(CGColor(srgbRed: tone, green: tone, blue: tone, alpha: 1))
            context.fill(CGRect(x: 0, y: CGFloat(index) * bandHeight, width: width, height: bandHeight))
        }
        return CaptureImage(cgImage: context.makeImage()!, scale: scale)
    }

    /// Lienzo que imita una ventana cualquiera, para ver las anotaciones sobre contenido real.
    /// - Parameter variant: genera lienzos de distinta forma y tono, para que una pila de
    ///   ejemplo se parezca a un conjunto real de capturas y no a la misma repetida.
    static func makeSyntheticCapture(scale: CGFloat = 2, variant: Int = 0) -> CaptureImage {
        let shapes: [(CGFloat, CGFloat)] = [(720, 460), (640, 380), (760, 300), (560, 520)]
        let shape = shapes[variant % shapes.count]
        let width: CGFloat = shape.0
        let height: CGFloat = shape.1
        let context = CGContext(data: nil,
                                width: Int(width * scale),
                                height: Int(height * scale),
                                bitsPerComponent: 8,
                                bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: scale, y: scale)

        // Fondo.
        context.setFillColor(CGColor(srgbRed: 0.97, green: 0.97, blue: 0.98, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Barra superior.
        context.setFillColor(CGColor(srgbRed: 0.90, green: 0.90, blue: 0.92, alpha: 1))
        context.fill(CGRect(x: 0, y: height - 42, width: width, height: 42))
        for (index, color) in [CGColor(srgbRed: 1, green: 0.37, blue: 0.34, alpha: 1),
                               CGColor(srgbRed: 1, green: 0.74, blue: 0.18, alpha: 1),
                               CGColor(srgbRed: 0.16, green: 0.79, blue: 0.25, alpha: 1)].enumerated() {
            context.setFillColor(color)
            context.fillEllipse(in: CGRect(x: 16 + CGFloat(index) * 20, y: height - 27, width: 12, height: 12))
        }

        // Barra lateral.
        context.setFillColor(CGColor(srgbRed: 0.93, green: 0.93, blue: 0.95, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 180, height: height - 42))
        for row in 0..<7 {
            context.setFillColor(CGColor(srgbRed: 0.78, green: 0.78, blue: 0.81, alpha: 1))
            context.fill(CGRect(x: 20, y: height - 90 - CGFloat(row) * 34, width: 120, height: 10))
        }

        // Bloques de contenido.
        for row in 0..<9 {
            let y = height - 90 - CGFloat(row) * 36
            let widthFactor = [0.9, 0.75, 0.85, 0.6, 0.8, 0.7, 0.88, 0.5, 0.78][row]
            context.setFillColor(CGColor(srgbRed: 0.80, green: 0.80, blue: 0.83, alpha: 1))
            context.fill(CGRect(x: 210, y: y, width: (width - 250) * widthFactor, height: 11))
        }

        // Un dato "sensible" que censurar con el blur.
        context.setFillColor(CGColor(srgbRed: 0.25, green: 0.28, blue: 0.35, alpha: 1))
        context.fill(CGRect(x: 210, y: 60, width: 260, height: 40))

        return CaptureImage(cgImage: context.makeImage()!, scale: scale)
    }

    static func addSampleAnnotations(to document: EditorDocument, variant: Int = 0) {
        // Todas las posiciones son relativas al tamaño de la captura: la muestra se usa con
        // lienzos de formas distintas y con coordenadas fijas las anotaciones se salían.
        let size = document.capture.logicalSize
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: size.width * x, y: size.height * y)
        }
        func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
            CGRect(x: size.width * x, y: size.height * y,
                   width: size.width * width, height: size.height * height)
        }

        // Cada captura de la pila lleva un color distinto, para distinguirlas de un vistazo.
        let colors: [AnnotationColor] = [.red, .blue, .green, .purple]
        document.color = colors[variant % colors.count]
        document.add(Annotation(shape: .rectangle(rect(0.28, 0.63, 0.42, 0.13)),
                                style: document.currentStyle))
        document.add(Annotation(shape: .arrow(from: point(0.78, 0.46), to: point(0.60, 0.62)),
                                style: document.currentStyle))

        document.color = .blue
        document.add(Annotation(shape: .ellipse(rect(0.03, 0.70, 0.21, 0.13)),
                                style: document.currentStyle))

        document.color = .green
        document.add(Annotation(shape: .pencil(points: (0..<40).map {
            point(0.30 + CGFloat($0) * 0.011, 0.38 + sin(Double($0) / 4) * 0.04)
        }), style: document.currentStyle))

        document.color = .purple
        document.fontSize = max(18, size.height * 0.06)
        document.textWidth = size.width * 0.42
        document.add(Annotation(shape: .text(origin: point(0.30, 0.80),
                                             string: "Revisar este bloque"),
                                style: document.currentStyle))
        document.fontSize = 28

        // Censura de un dato sensible.
        document.add(Annotation(shape: .blur(rect(0.28, 0.11, 0.38, 0.10)),
                                style: document.currentStyle))

        // Contadores numerados automáticamente.
        document.color = .orange
        for position in [point(0.08, 0.54), point(0.74, 0.72), point(0.89, 0.28)] {
            document.add(Annotation(shape: .counter(center: position, number: document.nextCounterNumber),
                                    style: document.currentStyle))
        }
        document.select(nil)
    }
}
