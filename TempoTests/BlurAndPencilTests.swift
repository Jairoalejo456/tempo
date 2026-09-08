import XCTest
@testable import Tempo

/// Ajustes continuos: intensidad del difuminado y grosor del trazo.
final class BlurAndPencilTests: XCTestCase {

    private let region = CGRect(x: 20, y: 20, width: 120, height: 120)

    // MARK: - Intensidad del blur

    func testStrongerBlurLooksDifferent() throws {
        let capture = TestSupport.makeTwoToneCapture(scale: 2)

        func compose(_ intensity: CGFloat) throws -> CGImage {
            let style = AnnotationStyle(color: .red, lineWidth: 4, fontSize: 28, blurIntensity: intensity)
            return try ImageExporter.compose(capture: capture,
                                             annotations: [Annotation(shape: .blur(region), style: style)])
        }

        let soft = try compose(0.1)
        let strong = try compose(1.0)
        XCTAssertGreaterThan(TestSupport.differingPixelCount(soft, strong), 100,
                             "Subir la intensidad cambia visiblemente el difuminado")
    }

    func testBlurRadiusGrowsWithIntensity() {
        let image = TestSupport.makeCapture(logicalWidth: 400, logicalHeight: 400, scale: 2).cgImage
        let low = CaptureImage.blurRadius(level: CaptureImage.level(for: 0), for: image)
        let mid = CaptureImage.blurRadius(level: CaptureImage.level(for: 0.5), for: image)
        let high = CaptureImage.blurRadius(level: CaptureImage.level(for: 1), for: image)

        XCTAssertLessThan(low, mid)
        XCTAssertLessThan(mid, high)
        XCTAssertGreaterThanOrEqual(low, 4, "Incluso al mínimo, el difuminado se nota")
    }

    func testBlurRadiusScalesWithImageSize() {
        let small = TestSupport.makeCapture(logicalWidth: 100, logicalHeight: 100, scale: 1).cgImage
        let large = TestSupport.makeCapture(logicalWidth: 1000, logicalHeight: 1000, scale: 1).cgImage
        let level = CaptureImage.level(for: 0.5)

        XCTAssertLessThan(CaptureImage.blurRadius(level: level, for: small),
                          CaptureImage.blurRadius(level: level, for: large),
                          "La censura debe ser igual de fuerte en proporción, no en píxeles")
    }

    func testIntensityIsQuantisedIntoLevels() {
        // Valores muy próximos comparten nivel, para no rehacer el filtro mientras se arrastra.
        XCTAssertEqual(CaptureImage.level(for: 0.50), CaptureImage.level(for: 0.51))
        XCTAssertNotEqual(CaptureImage.level(for: 0.10), CaptureImage.level(for: 0.90))
        XCTAssertEqual(CaptureImage.level(for: -5), 0, "Fuera de rango se recorta")
        XCTAssertEqual(CaptureImage.level(for: 42), CaptureImage.blurLevels)
    }

    func testBlurredImageIsCachedPerLevel() {
        let capture = TestSupport.makeCapture(logicalWidth: 120, logicalHeight: 120, scale: 1)
        let first = capture.blurredImage(intensity: 0.4)
        let again = capture.blurredImage(intensity: 0.4)
        XCTAssertTrue(first === again, "El mismo nivel reutiliza la imagen ya calculada")

        let other = capture.blurredImage(intensity: 1)
        XCTAssertFalse(first === other, "Un nivel distinto genera su propia imagen")
    }

    // MARK: - Estado del editor

    func testIntensityTravelsIntoNewAnnotations() {
        let document = EditorDocument(capture: TestSupport.makeCapture())
        document.blurIntensity = 0.8
        XCTAssertEqual(document.currentStyle.blurIntensity, 0.8)
    }

    func testIntensityAppliesToSelectedBlur() {
        let document = EditorDocument(capture: TestSupport.makeCapture())
        let blur = Annotation(shape: .blur(region), style: .default)
        document.add(blur)

        document.blurIntensity = 0.9
        document.applyBlurIntensityToSelection()
        XCTAssertEqual(document.annotations.first?.style.blurIntensity, 0.9)

        document.undo()
        XCTAssertEqual(document.annotations.first?.style.blurIntensity,
                       AnnotationStyle.defaultBlurIntensity, "El cambio se deshace")
    }

    func testIntensityIgnoresOtherTools() {
        let document = EditorDocument(capture: TestSupport.makeCapture())
        let rectangle = Annotation(shape: .rectangle(region), style: .default)
        document.add(rectangle)

        document.blurIntensity = 0.9
        document.applyBlurIntensityToSelection()
        XCTAssertEqual(document.annotations.first?.style.blurIntensity,
                       AnnotationStyle.defaultBlurIntensity,
                       "Sólo el blur usa la intensidad")
    }

    // MARK: - Grosor del lápiz

    func testPencilWidthAppliesToSelectedStroke() {
        let document = EditorDocument(capture: TestSupport.makeCapture())
        let stroke = Annotation(shape: .pencil(points: [CGPoint(x: 5, y: 5), CGPoint(x: 60, y: 60)]),
                                style: .default)
        document.add(stroke)

        document.lineWidth = 17
        document.applyLineWidthToSelection()
        XCTAssertEqual(document.annotations.first?.style.lineWidth, 17)
    }

    func testPencilWidthRangeIsSensible() {
        let range = EditorDocument.pencilWidthRange
        XCTAssertGreaterThanOrEqual(range.lowerBound, 1, "Un trazo siempre debe verse")
        XCTAssertLessThanOrEqual(range.upperBound, 40)
        XCTAssertTrue(range.contains(4), "El grosor por omisión cae dentro del rango")
    }

    func testThickerStrokeCoversMorePixels() throws {
        let capture = TestSupport.makeCapture(logicalWidth: 200, logicalHeight: 200, scale: 2,
                                              color: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        let points = [CGPoint(x: 20, y: 100), CGPoint(x: 180, y: 100)]

        func compose(_ width: CGFloat) throws -> CGImage {
            let style = AnnotationStyle(color: .red, lineWidth: width, fontSize: 28)
            return try ImageExporter.compose(capture: capture,
                                             annotations: [Annotation(shape: .pencil(points: points), style: style)])
        }

        let plain = try ImageExporter.compose(capture: capture, annotations: [])
        let thin = try compose(2)
        let thick = try compose(20)

        XCTAssertGreaterThan(TestSupport.differingPixelCount(plain, thick),
                             TestSupport.differingPixelCount(plain, thin),
                             "Un trazo más grueso pinta más píxeles")
    }
}
