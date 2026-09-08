import AppKit
import XCTest
@testable import Tempo

/// Salida: portapapeles, archivo en disco y archivo temporal para arrastrar.
final class ExportTests: XCTestCase {

    func testPNGDataIsValidAndKeepsSize() throws {
        let capture = TestSupport.makeCapture(logicalWidth: 160, logicalHeight: 100, scale: 2)
        let composed = try ImageExporter.compose(capture: capture, annotations: [])
        let data = try ImageExporter.pngData(from: composed)

        XCTAssertGreaterThan(data.count, 100)
        // Firma PNG.
        XCTAssertEqual(Array(data.prefix(4)), [0x89, 0x50, 0x4E, 0x47])

        let reloaded = NSBitmapImageRep(data: data)
        XCTAssertEqual(reloaded?.pixelsWide, 320)
        XCTAssertEqual(reloaded?.pixelsHigh, 200)
    }

    func testCopyToPasteboardProducesReadableImage() throws {
        let capture = TestSupport.makeCapture(logicalWidth: 120, logicalHeight: 80, scale: 2)
        let annotations = [Annotation(shape: .counter(center: CGPoint(x: 60, y: 40), number: 1), style: .default)]
        let composed = try ImageExporter.compose(capture: capture, annotations: annotations)

        try ImageExporter.copyToPasteboard(image: composed)

        let pasteboard = NSPasteboard.general
        // Lo que cualquier aplicación recibiría al pegar con ⌘V.
        let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage]
        let pasted = try XCTUnwrap(images?.first, "El portapapeles debe contener una imagen")
        XCTAssertEqual(pasted.size.width, 240, accuracy: 1)
        XCTAssertEqual(pasted.size.height, 160, accuracy: 1)

        XCTAssertNotNil(pasteboard.data(forType: .png), "También se ofrece PNG explícito")
    }

    func testWriteToDiskCreatesFile() throws {
        let capture = TestSupport.makeCapture(logicalWidth: 60, logicalHeight: 40, scale: 2)
        let composed = try ImageExporter.compose(capture: capture, annotations: [])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tempo-test-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }

        try ImageExporter.write(image: composed, to: url)

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertGreaterThan(attributes[.size] as? Int ?? 0, 0)

        let reloaded = NSImage(contentsOf: url)
        XCTAssertNotNil(reloaded)
    }

    func testTemporaryDragFileIsUniquePerCapture() throws {
        let capture = TestSupport.makeCapture(logicalWidth: 40, logicalHeight: 40, scale: 1)
        let composed = try ImageExporter.compose(capture: capture, annotations: [])
        let date = Date()

        let first = try ImageExporter.writeTemporaryFile(image: composed, date: date)
        let second = try ImageExporter.writeTemporaryFile(image: composed, date: date)
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }

        XCTAssertNotEqual(first, second, "Dos capturas del mismo segundo no se pisan")
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
        XCTAssertEqual(first.pathExtension, "png")
    }

    func testSuggestedFileName() {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 9
        components.hour = 14
        components.minute = 5
        components.second = 7
        let date = Calendar(identifier: .gregorian).date(from: components)!

        let name = ImageExporter.suggestedFileName(for: date)
        XCTAssertTrue(name.hasPrefix("Captura 2026-03-09"), "Nombre obtenido: \(name)")
        XCTAssertTrue(name.hasSuffix(".png"))
        XCTAssertFalse(name.contains("/"), "El nombre no puede contener separadores de ruta")
        XCTAssertFalse(name.contains(":"))
    }

    /// Un archivo recién arrastrado no puede borrarse: la aplicación que lo recibió puede
    /// quedarse con la ruta y leerlo más tarde, al enviar el mensaje.
    func testRecentDragFilesSurviveTheCleanup() throws {
        let capture = TestSupport.makeCapture(logicalWidth: 20, logicalHeight: 20, scale: 1)
        let composed = try ImageExporter.compose(capture: capture, annotations: [])
        let url = try ImageExporter.writeTemporaryFile(image: composed, date: Date())
        defer { try? FileManager.default.removeItem(at: url) }

        ImageExporter.cleanTemporaryFiles()

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path),
                      "Lo recién arrastrado sigue disponible para quien lo recibió")
    }

    func testExpiredDragFilesAreRemoved() throws {
        let capture = TestSupport.makeCapture(logicalWidth: 20, logicalHeight: 20, scale: 1)
        let composed = try ImageExporter.compose(capture: capture, annotations: [])
        let url = try ImageExporter.writeTemporaryFile(image: composed, date: Date())

        // Se envejece el archivo más allá del plazo.
        let old = Date().addingTimeInterval(-ImageExporter.dragFileLifetime - 60)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: url.path)

        ImageExporter.cleanTemporaryFiles()

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path),
                       "Lo que ya caducó sí se limpia")
    }

    func testCleanupUsesAGenerousLifetime() {
        XCTAssertGreaterThanOrEqual(ImageExporter.dragFileLifetime, 60 * 60,
                                    "El plazo debe cubrir de sobra el tiempo entre soltar y enviar")
    }

    /// El archivo que se arrastra debe llevar las anotaciones ya aplicadas.
    func testDragFileIncludesAnnotations() throws {
        let capture = TestSupport.makeCapture(logicalWidth: 100, logicalHeight: 100, scale: 2,
                                              color: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        let annotations = [Annotation(shape: .rectangle(CGRect(x: 10, y: 10, width: 80, height: 80)),
                                      style: .default)]
        let composed = try ImageExporter.compose(capture: capture, annotations: annotations)
        let url = try ImageExporter.writeTemporaryFile(image: composed, date: Date())
        defer { try? FileManager.default.removeItem(at: url) }

        let reloaded = try XCTUnwrap(NSImage(contentsOf: url))
        let reloadedCG = try XCTUnwrap(reloaded.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let plain = try ImageExporter.compose(capture: capture, annotations: [])
        XCTAssertGreaterThan(TestSupport.differingPixelCount(plain, reloadedCG), 100)
    }
}
