import AppKit
import XCTest
@testable import Tempo

/// Legibilidad de las anotaciones sobre cualquier fondo.
///
/// El caso que importa es el peor posible: una anotación sobre un fondo de su mismo color. Sin
/// contorno de contraste sería literalmente invisible, así que estas pruebas fallarían.
final class ContrastTests: XCTestCase {

    private func capture(colored color: AnnotationColor) -> CaptureImage {
        TestSupport.makeCapture(logicalWidth: 200, logicalHeight: 200, scale: 2, color: color.cgColor)
    }

    private func visiblePixels(of shape: AnnotationShape,
                               color: AnnotationColor,
                               onBackground background: AnnotationColor) throws -> Int {
        let base = capture(colored: background)
        let style = AnnotationStyle(color: color, lineWidth: 4, fontSize: 30)
        let plain = try ImageExporter.compose(capture: base, annotations: [])
        let drawn = try ImageExporter.compose(capture: base,
                                              annotations: [Annotation(shape: shape, style: style)])
        return TestSupport.differingPixelCount(plain, drawn)
    }

    // MARK: - El peor caso: el mismo color que el fondo

    func testEveryToolStaysVisibleOnItsOwnColour() throws {
        let shapes: [AnnotationShape] = [
            .rectangle(CGRect(x: 40, y: 40, width: 120, height: 100)),
            .ellipse(CGRect(x: 40, y: 40, width: 120, height: 100)),
            .arrow(from: CGPoint(x: 30, y: 30), to: CGPoint(x: 160, y: 150)),
            .pencil(points: (0..<20).map { CGPoint(x: 30 + Double($0) * 7, y: 100) }),
            .text(origin: CGPoint(x: 30, y: 90), string: "Abc"),
            .counter(center: CGPoint(x: 100, y: 100), number: 7)
        ]

        for color in AnnotationColor.palette {
            for shape in shapes {
                let changed = try visiblePixels(of: shape, color: color, onBackground: color)
                XCTAssertGreaterThan(changed, 80,
                    "\(shape.tool.rawValue) del mismo color que el fondo debe seguir viéndose")
            }
        }
    }

    func testTextStaysVisibleOnBlackAndOnWhite() throws {
        let shape = AnnotationShape.text(origin: CGPoint(x: 20, y: 90), string: "Revisar")

        for background in [AnnotationColor.black, .white] {
            for color in AnnotationColor.palette {
                let changed = try visiblePixels(of: shape, color: color, onBackground: background)
                XCTAssertGreaterThan(changed, 60,
                    "Texto \(color) sobre fondo \(background) debe leerse")
            }
        }
    }

    // MARK: - Elección del contorno

    func testHaloOpposesTheColourLuminance() {
        func luminance(of cgColor: CGColor) -> CGFloat {
            let components = cgColor.components ?? [0, 0, 0, 1]
            guard components.count >= 3 else { return 0 }
            return 0.299 * components[0] + 0.587 * components[1] + 0.114 * components[2]
        }

        // Un color claro se rodea de oscuro…
        XCTAssertLessThan(luminance(of: AnnotationRenderer.haloColor(for: .white)), 0.3)
        XCTAssertLessThan(luminance(of: AnnotationRenderer.haloColor(for: .yellow)), 0.3)
        // …y uno oscuro, de claro.
        XCTAssertGreaterThan(luminance(of: AnnotationRenderer.haloColor(for: .black)), 0.7)
        XCTAssertGreaterThan(luminance(of: AnnotationRenderer.haloColor(for: .blue)), 0.7)
        XCTAssertGreaterThan(luminance(of: AnnotationRenderer.haloColor(for: .red)), 0.7)
    }

    func testHaloGrowsWithTheStroke() {
        let thin = AnnotationStyle(color: .red, lineWidth: 2, fontSize: 20)
        let thick = AnnotationStyle(color: .red, lineWidth: 12, fontSize: 20)
        XCTAssertLessThan(AnnotationRenderer.haloWidth(for: thin),
                          AnnotationRenderer.haloWidth(for: thick))
        XCTAssertGreaterThanOrEqual(AnnotationRenderer.haloWidth(for: thin), 1.5,
                                    "Incluso un trazo fino necesita un borde apreciable")
    }

    // MARK: - El blur no lleva contorno

    func testBlurHasNoOutline() throws {
        let base = TestSupport.makeTwoToneCapture(scale: 2)
        let region = CGRect(x: 40, y: 40, width: 60, height: 60)
        let blurred = try ImageExporter.compose(
            capture: base,
            annotations: [Annotation(shape: .blur(region), style: .default)])
        let plain = try ImageExporter.compose(capture: base, annotations: [])

        // Un punto claramente fuera de la región no puede haber cambiado: si el blur pintase un
        // contorno alrededor, ahí habría color.
        let outside = TestSupport.pixel(blurred, x: 300, y: 40)
        let original = TestSupport.pixel(plain, x: 300, y: 40)
        XCTAssertEqual(outside.r, original.r, accuracy: 0.02)
        XCTAssertEqual(outside.g, original.g, accuracy: 0.02)
        XCTAssertEqual(outside.b, original.b, accuracy: 0.02)
    }

    // MARK: - El contorno no altera la geometría

    func testOutlineDoesNotMoveTheAnnotation() {
        let rect = CGRect(x: 40, y: 40, width: 120, height: 100)
        let annotation = Annotation(shape: .rectangle(rect), style: .default)
        // Los tiradores y la caja siguen los valores del modelo, no lo que se pinte alrededor.
        XCTAssertEqual(annotation.localBounds, rect)
    }
}
