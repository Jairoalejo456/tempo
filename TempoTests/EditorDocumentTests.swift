import XCTest
@testable import Tempo

/// Estado del editor: historial, numeración de contadores y descarte de gestos vacíos.
final class EditorDocumentTests: XCTestCase {

    private func makeDocument() -> EditorDocument {
        EditorDocument(capture: TestSupport.makeCapture())
    }

    private func rectangle(_ rect: CGRect = CGRect(x: 10, y: 10, width: 50, height: 40)) -> Annotation {
        Annotation(shape: .rectangle(rect), style: .default)
    }

    // MARK: - Deshacer y rehacer

    func testUndoRedoRestoresAnnotations() {
        let document = makeDocument()
        XCTAssertFalse(document.canUndo)
        XCTAssertFalse(document.canRedo)

        document.add(rectangle())
        document.add(Annotation(shape: .arrow(from: .zero, to: CGPoint(x: 60, y: 60)), style: .default))
        XCTAssertEqual(document.annotations.count, 2)
        XCTAssertTrue(document.canUndo)

        document.undo()
        XCTAssertEqual(document.annotations.count, 1)
        XCTAssertTrue(document.canRedo)

        document.undo()
        XCTAssertEqual(document.annotations.count, 0)
        XCTAssertFalse(document.canUndo)

        document.redo()
        document.redo()
        XCTAssertEqual(document.annotations.count, 2)
        XCTAssertFalse(document.canRedo)
    }

    func testNewEditClearsRedoStack() {
        let document = makeDocument()
        document.add(rectangle())
        document.undo()
        XCTAssertTrue(document.canRedo)

        document.add(rectangle(CGRect(x: 0, y: 0, width: 20, height: 20)))
        XCTAssertFalse(document.canRedo, "Una edición nueva invalida el historial de rehacer")
    }

    func testUndoWithEmptyHistoryDoesNothing() {
        let document = makeDocument()
        document.undo()
        document.redo()
        XCTAssertTrue(document.annotations.isEmpty)
    }

    func testRemoveLast() {
        let document = makeDocument()
        document.add(rectangle())
        document.removeLast()
        XCTAssertTrue(document.annotations.isEmpty)
        document.undo()
        XCTAssertEqual(document.annotations.count, 1, "Borrar también se puede deshacer")
    }

    // MARK: - Contadores

    func testCountersIncrementAutomatically() {
        let document = makeDocument()
        for expected in 1...4 {
            XCTAssertEqual(document.nextCounterNumber, expected)
            document.add(Annotation(shape: .counter(center: CGPoint(x: 20 * expected, y: 30),
                                                    number: document.nextCounterNumber),
                                    style: .default))
        }

        let numbers = document.annotations.compactMap { annotation -> Int? in
            if case let .counter(_, number) = annotation.shape { return number }
            return nil
        }
        XCTAssertEqual(numbers, [1, 2, 3, 4])
    }

    func testCounterNumberingFollowsUndo() {
        let document = makeDocument()
        for _ in 1...3 {
            document.add(Annotation(shape: .counter(center: .zero, number: document.nextCounterNumber), style: .default))
        }
        XCTAssertEqual(document.nextCounterNumber, 4)

        document.undo()
        XCTAssertEqual(document.nextCounterNumber, 3, "Al deshacer, el siguiente contador vuelve atrás")

        document.redo()
        XCTAssertEqual(document.nextCounterNumber, 4)
    }

    func testCountersIgnoreOtherAnnotations() {
        let document = makeDocument()
        document.add(rectangle())
        XCTAssertEqual(document.nextCounterNumber, 1)
    }

    // MARK: - Gestos sin contenido

    func testEmptyGesturesAreDiscarded() {
        let document = makeDocument()
        document.add(Annotation(shape: .rectangle(CGRect(x: 10, y: 10, width: 0, height: 0)), style: .default))
        document.add(Annotation(shape: .arrow(from: CGPoint(x: 5, y: 5), to: CGPoint(x: 5, y: 6)), style: .default))
        document.add(Annotation(shape: .text(origin: .zero, string: "   "), style: .default))
        document.add(Annotation(shape: .pencil(points: [CGPoint(x: 1, y: 1)]), style: .default))

        XCTAssertTrue(document.annotations.isEmpty, "Un clic sin arrastre o un texto vacío no crean anotaciones")
        XCTAssertFalse(document.canUndo, "Tampoco ensucian el historial")
    }

    func testMeaningfulGesturesAreKept() {
        let document = makeDocument()
        document.add(Annotation(shape: .text(origin: .zero, string: "Hola"), style: .default))
        document.add(Annotation(shape: .pencil(points: [CGPoint(x: 1, y: 1), CGPoint(x: 20, y: 20)]), style: .default))
        XCTAssertEqual(document.annotations.count, 2)
    }

    // MARK: - Estilo activo

    func testCurrentStyleReflectsSelection() {
        let document = makeDocument()
        document.color = .blue
        document.lineWidth = 7
        document.fontSize = 40
        XCTAssertEqual(document.currentStyle.color, .blue)
        XCTAssertEqual(document.currentStyle.lineWidth, 7)
        XCTAssertEqual(document.currentStyle.fontSize, 40)
    }

    func testDraftIsRenderedButNotCommitted() {
        let document = makeDocument()
        document.draft = rectangle()
        XCTAssertEqual(document.renderableAnnotations.count, 1)
        XCTAssertTrue(document.annotations.isEmpty)
        XCTAssertFalse(document.canUndo)
    }
}
