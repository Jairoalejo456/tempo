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

    /// Lienzo que imita una ventana cualquiera, para ver las anotaciones sobre contenido real.
    static func makeSyntheticCapture(scale: CGFloat = 2) -> CaptureImage {
        let width: CGFloat = 720
        let height: CGFloat = 460
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

    static func addSampleAnnotations(to document: EditorDocument) {
        document.color = .red
        document.add(Annotation(shape: .rectangle(CGRect(x: 200, y: 300, width: 300, height: 60)),
                                style: document.currentStyle))

        document.add(Annotation(shape: .arrow(from: CGPoint(x: 560, y: 220), to: CGPoint(x: 430, y: 300)),
                                style: document.currentStyle))

        document.color = .blue
        document.add(Annotation(shape: .ellipse(CGRect(x: 20, y: 330, width: 150, height: 60)),
                                style: document.currentStyle))

        document.color = .green
        document.add(Annotation(shape: .pencil(points: (0..<40).map {
            CGPoint(x: 220 + Double($0) * 8, y: 180 + sin(Double($0) / 4) * 18)
        }), style: document.currentStyle))

        document.color = .purple
        document.add(Annotation(shape: .text(origin: CGPoint(x: 210, y: 400), string: "Revisar este bloque"),
                                style: document.currentStyle))

        // Censura del dato sensible.
        document.add(Annotation(shape: .blur(CGRect(x: 205, y: 55, width: 270, height: 50)),
                                style: document.currentStyle))

        // Contadores numerados automáticamente.
        document.color = .orange
        for point in [CGPoint(x: 60, y: 250), CGPoint(x: 530, y: 330), CGPoint(x: 640, y: 130)] {
            document.add(Annotation(shape: .counter(center: point, number: document.nextCounterNumber),
                                    style: document.currentStyle))
        }
    }
}
