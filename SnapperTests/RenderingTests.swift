import AppKit
import XCTest
@testable import Snapper

/// Comprueba que cada herramienta pinta realmente sobre la imagen y que la exportación
/// conserva la resolución nativa (Retina).
final class RenderingTests: XCTestCase {

    private let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)

    // MARK: - Resolución

    func testComposeKeepsNativePixelSize() throws {
        let capture = TestSupport.makeCapture(logicalWidth: 300, logicalHeight: 200, scale: 2)
        XCTAssertEqual(capture.logicalSize, CGSize(width: 300, height: 200))
        XCTAssertEqual(capture.pixelSize, CGSize(width: 600, height: 400))

        let composed = try ImageExporter.compose(capture: capture, annotations: [])
        XCTAssertEqual(composed.width, 600, "Una captura Retina se exporta a resolución completa")
        XCTAssertEqual(composed.height, 400)
    }

    func testComposeAtScaleOne() throws {
        let capture = TestSupport.makeCapture(logicalWidth: 120, logicalHeight: 90, scale: 1)
        let composed = try ImageExporter.compose(capture: capture, annotations: [])
        XCTAssertEqual(composed.width, 120)
        XCTAssertEqual(composed.height, 90)
    }

    func testEmptyDocumentMatchesOriginal() throws {
        let capture = TestSupport.makeTwoToneCapture()
        let composed = try ImageExporter.compose(capture: capture, annotations: [])
        XCTAssertEqual(TestSupport.differingPixelCount(capture.cgImage, composed), 0,
                       "Sin anotaciones, la imagen exportada es idéntica a la capturada")
    }

    // MARK: - Cada herramienta pinta

    private func assertDraws(_ shape: AnnotationShape,
                             style: AnnotationStyle = .default,
                             capture: CaptureImage? = nil,
                             file: StaticString = #filePath,
                             line: UInt = #line) throws {
        let base = capture ?? TestSupport.makeCapture(logicalWidth: 200, logicalHeight: 200, scale: 2, color: white)
        let original = try ImageExporter.compose(capture: base, annotations: [])
        let annotated = try ImageExporter.compose(capture: base, annotations: [Annotation(shape: shape, style: style)])
        let changed = TestSupport.differingPixelCount(original, annotated)
        XCTAssertGreaterThan(changed, 50, "La herramienta \(shape.tool.rawValue) no dibujó nada", file: file, line: line)
    }

    func testArrowDraws() throws {
        try assertDraws(.arrow(from: CGPoint(x: 20, y: 20), to: CGPoint(x: 160, y: 150)))
    }

    func testRectangleDraws() throws {
        try assertDraws(.rectangle(CGRect(x: 30, y: 30, width: 120, height: 90)))
    }

    func testEllipseDraws() throws {
        try assertDraws(.ellipse(CGRect(x: 30, y: 30, width: 120, height: 90)))
    }

    func testPencilDraws() throws {
        let points = (0..<40).map { CGPoint(x: 20 + Double($0) * 3, y: 100 + sin(Double($0) / 4) * 30) }
        try assertDraws(.pencil(points: points))
    }

    func testTextDraws() throws {
        try assertDraws(.text(origin: CGPoint(x: 20, y: 100), string: "Revisar esto"))
    }

    func testCounterDraws() throws {
        try assertDraws(.counter(center: CGPoint(x: 100, y: 100), number: 1))
    }

    func testBlurChangesOnlyItsRegion() throws {
        let capture = TestSupport.makeTwoToneCapture(scale: 2)
        let region = CGRect(x: 10, y: 10, width: 40, height: 40)
        let original = try ImageExporter.compose(capture: capture, annotations: [])
        let blurred = try ImageExporter.compose(capture: capture,
                                                annotations: [Annotation(shape: .blur(region), style: .default)])

        XCTAssertGreaterThan(TestSupport.differingPixelCount(original, blurred), 100,
                             "El blur debe alterar la zona seleccionada")

        // Un píxel muy lejos de la región difuminada no debe cambiar.
        let far = TestSupport.pixel(blurred, x: 180, y: 20)
        let farOriginal = TestSupport.pixel(original, x: 180, y: 20)
        XCTAssertEqual(far.r, farOriginal.r, accuracy: 0.02, "Fuera de la región, la imagen se conserva")
        XCTAssertEqual(far.g, farOriginal.g, accuracy: 0.02)
        XCTAssertEqual(far.b, farOriginal.b, accuracy: 0.02)
    }

    // MARK: - Color

    func testColorSelectionChangesResult() throws {
        let capture = TestSupport.makeCapture(logicalWidth: 100, logicalHeight: 100, scale: 2, color: white)
        let rect = CGRect(x: 20, y: 20, width: 60, height: 60)

        let red = try ImageExporter.compose(capture: capture, annotations: [
            Annotation(shape: .rectangle(rect), style: AnnotationStyle(color: .red, lineWidth: 6, fontSize: 28))
        ])
        let blue = try ImageExporter.compose(capture: capture, annotations: [
            Annotation(shape: .rectangle(rect), style: AnnotationStyle(color: .blue, lineWidth: 6, fontSize: 28))
        ])

        XCTAssertGreaterThan(TestSupport.differingPixelCount(red, blue), 50,
                             "Cambiar el color cambia el resultado exportado")
    }

    func testCounterUsesSelectedColor() throws {
        let capture = TestSupport.makeCapture(logicalWidth: 100, logicalHeight: 100, scale: 2, color: white)
        let shape = AnnotationShape.counter(center: CGPoint(x: 50, y: 50), number: 3)
        let green = try ImageExporter.compose(capture: capture, annotations: [
            Annotation(shape: shape, style: AnnotationStyle(color: .green, lineWidth: 4, fontSize: 28))
        ])
        // Se muestrea dentro del círculo pero fuera del glifo del número, para leer el relleno.
        let sample = TestSupport.pixel(green, x: 128, y: 100)
        XCTAssertLessThan(sample.r, 0.6, "El relleno del contador usa el color elegido")
        XCTAssertGreaterThan(sample.g, sample.r, "y ese color es el verde seleccionado")
    }

    func testLineWidthAffectsResult() throws {
        let capture = TestSupport.makeCapture(logicalWidth: 100, logicalHeight: 100, scale: 2, color: white)
        let rect = CGRect(x: 20, y: 20, width: 60, height: 60)
        let thin = try ImageExporter.compose(capture: capture, annotations: [
            Annotation(shape: .rectangle(rect), style: AnnotationStyle(color: .red, lineWidth: 2, fontSize: 28))
        ])
        let thick = try ImageExporter.compose(capture: capture, annotations: [
            Annotation(shape: .rectangle(rect), style: AnnotationStyle(color: .red, lineWidth: 8, fontSize: 28))
        ])
        XCTAssertGreaterThan(TestSupport.differingPixelCount(thin, thick), 50)
    }

    // MARK: - Composición acumulada

    func testAllToolsTogether() throws {
        let capture = TestSupport.makeCapture(logicalWidth: 400, logicalHeight: 300, scale: 2, color: white)
        let annotations: [Annotation] = [
            Annotation(shape: .blur(CGRect(x: 10, y: 10, width: 80, height: 60)), style: .default),
            Annotation(shape: .rectangle(CGRect(x: 100, y: 20, width: 80, height: 60)), style: .default),
            Annotation(shape: .ellipse(CGRect(x: 200, y: 20, width: 80, height: 60)), style: .default),
            Annotation(shape: .arrow(from: CGPoint(x: 30, y: 150), to: CGPoint(x: 150, y: 220)), style: .default),
            Annotation(shape: .pencil(points: [CGPoint(x: 200, y: 150), CGPoint(x: 240, y: 190), CGPoint(x: 300, y: 160)]), style: .default),
            Annotation(shape: .text(origin: CGPoint(x: 40, y: 250), string: "Aquí"), style: .default),
            Annotation(shape: .counter(center: CGPoint(x: 350, y: 250), number: 1), style: .default)
        ]
        let composed = try ImageExporter.compose(capture: capture, annotations: annotations)
        XCTAssertEqual(composed.width, 800)
        XCTAssertEqual(composed.height, 600)

        let original = try ImageExporter.compose(capture: capture, annotations: [])
        XCTAssertGreaterThan(TestSupport.differingPixelCount(original, composed), 1000)
    }

    /// La miniatura, el lienzo y la exportación usan el mismo renderizador: componer dos veces
    /// el mismo documento debe dar exactamente el mismo resultado.
    func testCompositionIsDeterministic() throws {
        let capture = TestSupport.makeCapture(logicalWidth: 150, logicalHeight: 150, scale: 2)
        let annotations = [Annotation(shape: .counter(center: CGPoint(x: 70, y: 70), number: 2), style: .default)]
        let first = try ImageExporter.compose(capture: capture, annotations: annotations)
        let second = try ImageExporter.compose(capture: capture, annotations: annotations)
        XCTAssertEqual(TestSupport.differingPixelCount(first, second), 0)
    }
}
