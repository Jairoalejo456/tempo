import AppKit
import XCTest
@testable import Tempo

/// Recorte del encuadre y tamaño de la imagen al copiar.
final class CropAndExportTests: XCTestCase {

    // MARK: - Recortar

    private func makeDocument() -> EditorDocument {
        EditorDocument(capture: TestSupport.makeCapture(logicalWidth: 400, logicalHeight: 300, scale: 2))
    }

    func testCropChangesTheCaptureSize() {
        let document = makeDocument()
        XCTAssertTrue(document.crop(to: CGRect(x: 50, y: 40, width: 200, height: 150)))

        XCTAssertEqual(document.capture.logicalSize, CGSize(width: 200, height: 150))
        XCTAssertEqual(document.capture.pixelSize, CGSize(width: 400, height: 300),
                       "El recorte se hace sobre los píxeles nativos: no se pierde resolución")
    }

    func testCropMovesTheAnnotationsWithIt() {
        let document = makeDocument()
        document.add(Annotation(shape: .rectangle(CGRect(x: 100, y: 100, width: 60, height: 40)),
                                style: .default))

        document.crop(to: CGRect(x: 50, y: 40, width: 200, height: 150))

        guard case let .rectangle(rect) = document.annotations.first?.shape else {
            return XCTFail("La anotación desapareció")
        }
        XCTAssertEqual(rect.origin.x, 50, "Se desplaza tanto como el recorte")
        XCTAssertEqual(rect.origin.y, 60)
        XCTAssertEqual(rect.size, CGSize(width: 60, height: 40), "Sin deformarse")
    }

    func testCropDropsAnnotationsLeftOutside() {
        let document = makeDocument()
        document.add(Annotation(shape: .rectangle(CGRect(x: 10, y: 10, width: 20, height: 20)),
                                style: .default))
        document.add(Annotation(shape: .rectangle(CGRect(x: 150, y: 120, width: 40, height: 30)),
                                style: .default))

        document.crop(to: CGRect(x: 120, y: 100, width: 200, height: 150))

        XCTAssertEqual(document.annotations.count, 1,
                       "Lo que queda fuera del nuevo encuadre se descarta")
    }

    func testCropIsUndoable() {
        let document = makeDocument()
        document.add(Annotation(shape: .rectangle(CGRect(x: 10, y: 10, width: 20, height: 20)),
                                style: .default))
        let originalSize = document.capture.logicalSize

        document.crop(to: CGRect(x: 100, y: 100, width: 150, height: 100))
        XCTAssertNotEqual(document.capture.logicalSize, originalSize)

        document.undo()
        XCTAssertEqual(document.capture.logicalSize, originalSize,
                       "Deshacer devuelve también los píxeles que se habían quitado")
        XCTAssertEqual(document.annotations.count, 1)
    }

    func testCropToTheWholeImageDoesNothing() {
        let document = makeDocument()
        XCTAssertFalse(document.crop(to: document.capture.logicalBounds),
                       "Recortar al encuadre completo no es un cambio")
        XCTAssertFalse(document.canUndo)
    }

    func testCropIsClampedToTheCapture() {
        let document = makeDocument()
        // Un rectángulo que se sale por todos lados se recorta a lo que hay.
        document.crop(to: CGRect(x: -100, y: -100, width: 1000, height: 1000))
        XCTAssertLessThanOrEqual(document.capture.logicalSize.width, 400)
        XCTAssertLessThanOrEqual(document.capture.logicalSize.height, 300)
    }

    func testEmptyCropIsRejected() {
        let document = makeDocument()
        XCTAssertFalse(document.crop(to: CGRect(x: 10, y: 10, width: 0, height: 0)))
    }

    func testCroppedImageKeepsTheRightPixels() throws {
        // Mitad izquierda negra, mitad derecha blanca.
        let width = 200, height = 100
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 100, height: height))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 100, y: 0, width: 100, height: height))
        let capture = CaptureImage(cgImage: context.makeImage()!, scale: 1)

        // Se recorta sólo la mitad derecha.
        let right = try XCTUnwrap(capture.cropped(to: CGRect(x: 100, y: 0, width: 100, height: 100)))
        let sample = TestSupport.pixel(right.cgImage, x: 50, y: 50)
        XCTAssertGreaterThan(sample.r, 0.9, "La mitad recortada es la blanca")
    }

    func testCropResetsTheZoom() {
        let document = makeDocument()
        document.zoomFactor = 3
        document.crop(to: CGRect(x: 20, y: 20, width: 100, height: 80))
        XCTAssertEqual(document.zoomFactor, 1, "Tras recortar, la vista vuelve a encajar")
    }

    // MARK: - Tamaño al copiar

    func testResizeRespectsTheLongestSide() {
        let capture = TestSupport.makeCapture(logicalWidth: 1400, logicalHeight: 700, scale: 2)
        let reduced = ImageExporter.resized(capture.cgImage, maximumSide: 1600)

        XCTAssertEqual(reduced.width, 1600)
        XCTAssertEqual(reduced.height, 800, "Se conserva la proporción")
    }

    func testResizeLeavesSmallImagesAlone() {
        let capture = TestSupport.makeCapture(logicalWidth: 300, logicalHeight: 200, scale: 1)
        let same = ImageExporter.resized(capture.cgImage, maximumSide: 1600)
        XCTAssertEqual(same.width, 300, "Una imagen que ya cabe no se toca")
        XCTAssertEqual(same.height, 200)
    }

    func testCopySizeOptions() {
        XCTAssertNil(Preferences.CopySize.original.maximumSide, "El original no se reduce")
        XCTAssertEqual(Preferences.CopySize.standard.maximumSide, 1600)
        XCTAssertLessThan(Preferences.CopySize.compact.maximumSide!,
                          Preferences.CopySize.large.maximumSide!)
    }

    func testCopyToPasteboardHonoursTheLimit() throws {
        let capture = TestSupport.makeCapture(logicalWidth: 1200, logicalHeight: 900, scale: 2)
        let composed = try ImageExporter.compose(capture: capture, annotations: [])
        XCTAssertEqual(composed.width, 2400)

        try ImageExporter.copyToPasteboard(image: composed, maximumSide: 1600)
        let pasted = NSPasteboard.general.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage]
        let image = try XCTUnwrap(pasted?.first)
        XCTAssertEqual(image.size.width, 1600, accuracy: 2)
    }

    func testSavingIsNeverReduced() throws {
        // Guardar en disco conserva el original: la reducción es sólo para el portapapeles.
        let capture = TestSupport.makeCapture(logicalWidth: 1200, logicalHeight: 900, scale: 2)
        let composed = try ImageExporter.compose(capture: capture, annotations: [])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tempo-full-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }

        try ImageExporter.write(image: composed, to: url)
        let reloaded = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: url)))
        XCTAssertEqual(reloaded.pixelsWide, 2400)
    }
}
