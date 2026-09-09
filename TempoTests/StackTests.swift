import AppKit
import XCTest
@testable import Tempo

/// Edición de varias capturas: cada una conserva lo suyo y la barra sigue a la activa.
final class StackTests: XCTestCase {

    private func makeDocuments(_ count: Int) -> [EditorDocument] {
        (0..<count).map { index in
            EditorDocument(capture: TestSupport.makeCapture(logicalWidth: 200 + index * 20,
                                                            logicalHeight: 150,
                                                            scale: 2))
        }
    }

    // MARK: - Estado de la pila

    func testStackStartsOnTheRequestedCapture() {
        let documents = makeDocuments(3)
        let stack = EditorStack(documents: documents, activeID: documents[1].id)

        XCTAssertEqual(stack.active.id, documents[1].id)
        XCTAssertEqual(stack.count, 3)
        XCTAssertTrue(stack.holdsSeveral)
        XCTAssertEqual(stack.position(of: documents[2].id), 3, "Las posiciones se cuentan desde 1")
    }

    func testSingleCaptureIsNotAStack() {
        let stack = EditorStack(documents: makeDocuments(1))
        XCTAssertFalse(stack.holdsSeveral, "Con una sola captura no hay tira lateral que mostrar")
    }

    func testActivatingChangesTheActiveDocument() {
        let documents = makeDocuments(3)
        let stack = EditorStack(documents: documents)
        XCTAssertEqual(stack.active.id, documents[0].id)

        stack.activate(documents[2].id)
        XCTAssertEqual(stack.active.id, documents[2].id)
    }

    func testActivatingAnUnknownCaptureIsIgnored() {
        let documents = makeDocuments(2)
        let stack = EditorStack(documents: documents)
        stack.activate(UUID())
        XCTAssertEqual(stack.active.id, documents[0].id)
    }

    /// Cambiar de captura no puede dejar tiradores visibles en la que se abandona.
    func testSwitchingClearsTheSelectionOfThePreviousCapture() {
        let documents = makeDocuments(2)
        let stack = EditorStack(documents: documents)

        let annotation = Annotation(shape: .rectangle(CGRect(x: 10, y: 10, width: 40, height: 30)),
                                    style: .default)
        documents[0].add(annotation)
        XCTAssertNotNil(documents[0].selectedID)

        stack.activate(documents[1].id)
        XCTAssertNil(documents[0].selectedID)
    }

    // MARK: - Cada captura mantiene lo suyo

    func testEachCaptureKeepsItsOwnAnnotationsAndHistory() {
        let documents = makeDocuments(2)
        let stack = EditorStack(documents: documents)

        documents[0].add(Annotation(shape: .rectangle(CGRect(x: 5, y: 5, width: 30, height: 20)),
                                    style: .default))
        stack.activate(documents[1].id)
        documents[1].add(Annotation(shape: .counter(center: CGPoint(x: 20, y: 20), number: 1),
                                    style: .default))

        XCTAssertEqual(documents[0].annotations.count, 1)
        XCTAssertEqual(documents[1].annotations.count, 1)
        XCTAssertEqual(documents[0].annotations.first?.tool, .rectangle)
        XCTAssertEqual(documents[1].annotations.first?.tool, .counter)

        // Deshacer en una no toca a la otra.
        documents[1].undo()
        XCTAssertTrue(documents[1].annotations.isEmpty)
        XCTAssertEqual(documents[0].annotations.count, 1, "El historial es de cada captura")
    }

    func testCountersAreNumberedPerCapture() {
        let documents = makeDocuments(2)
        for document in documents {
            document.add(Annotation(shape: .counter(center: .zero, number: document.nextCounterNumber),
                                    style: .default))
        }
        XCTAssertEqual(documents[0].annotations.first?.counterNumber, 1)
        XCTAssertEqual(documents[1].annotations.first?.counterNumber, 1,
                       "Cada captura empieza a numerar desde uno")
    }

    // MARK: - Quitar capturas

    func testRemovingACaptureActivatesAnother() {
        let documents = makeDocuments(3)
        let stack = EditorStack(documents: documents, activeID: documents[1].id)

        XCTAssertTrue(stack.remove(documents[1].id), "Quedan capturas, la ventana sigue abierta")
        XCTAssertEqual(stack.count, 2)
        XCTAssertNotEqual(stack.activeID, documents[1].id)
        XCTAssertNotNil(stack.document(with: stack.activeID))
    }

    func testRemovingTheLastCaptureClosesTheWindow() {
        let documents = makeDocuments(1)
        let stack = EditorStack(documents: documents)
        XCTAssertFalse(stack.remove(documents[0].id), "Sin capturas no hay nada que editar")
    }

    func testRemovingAnInactiveCaptureKeepsTheActiveOne() {
        let documents = makeDocuments(3)
        let stack = EditorStack(documents: documents, activeID: documents[0].id)
        stack.remove(documents[2].id)
        XCTAssertEqual(stack.activeID, documents[0].id)
        XCTAssertEqual(stack.count, 2)
    }

    func testAddingIgnoresDuplicates() {
        let documents = makeDocuments(2)
        let stack = EditorStack(documents: documents)
        stack.add(documents[0])
        XCTAssertEqual(stack.count, 2)
    }

    // MARK: - Unir varias capturas en una imagen

    func testCombinedImageStacksThemVertically() throws {
        let documents = makeDocuments(3)
        let images = try documents.map { try ImageExporter.compose(document: $0) }
        let combined = try ImageExporter.combineVertically(images)

        let widest = images.map(\.width).max() ?? 0
        let totalHeight = images.reduce(0) { $0 + $1.height }
            + ImageExporter.combinedSpacing * (images.count - 1)

        XCTAssertEqual(combined.width, widest, "Toma el ancho de la más ancha")
        XCTAssertEqual(combined.height, totalHeight, "Y suma las alturas más la separación")
    }

    func testCombiningASingleImageReturnsItUntouched() throws {
        let document = makeDocuments(1)[0]
        let image = try ImageExporter.compose(document: document)
        let combined = try ImageExporter.combineVertically([image])
        XCTAssertEqual(combined.width, image.width)
        XCTAssertEqual(combined.height, image.height)
    }

    func testCombiningNothingFails() {
        XCTAssertThrowsError(try ImageExporter.combineVertically([]))
    }

    func testCombinedImageKeepsEveryCaptureVisible() throws {
        // Tres capturas de colores distintos: las tres deben aparecer en el resultado.
        let colors: [CGColor] = [
            CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1),
            CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1),
            CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)
        ]
        let images = try colors.map { color in
            try ImageExporter.compose(capture: TestSupport.makeCapture(logicalWidth: 60, logicalHeight: 40,
                                                                       scale: 1, color: color),
                                      annotations: [])
        }
        let combined = try ImageExporter.combineVertically(images)

        // Se muestrea el centro de cada franja, de arriba abajo.
        let first = TestSupport.pixel(combined, x: 30, y: 20)
        let last = TestSupport.pixel(combined, x: 30, y: combined.height - 20)
        XCTAssertGreaterThan(first.r, 0.8, "Arriba está la primera captura")
        XCTAssertGreaterThan(last.b, 0.8, "Abajo está la última")
    }
}
