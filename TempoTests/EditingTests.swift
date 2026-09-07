import AppKit
import XCTest
@testable import Tempo

/// Anotaciones editables: seleccionar, mover, redimensionar, girar y renumerar.
final class EditingTests: XCTestCase {

    private func makeDocument() -> EditorDocument {
        EditorDocument(capture: TestSupport.makeCapture(logicalWidth: 400, logicalHeight: 300))
    }

    private let rect = CGRect(x: 100, y: 100, width: 80, height: 60)

    private func addRectangle(to document: EditorDocument) -> Annotation {
        let annotation = Annotation(shape: .rectangle(rect), style: .default)
        document.add(annotation)
        return document.annotations.last!
    }

    // MARK: - Selección

    func testNewAnnotationBecomesSelected() {
        let document = makeDocument()
        let annotation = addRectangle(to: document)
        XCTAssertEqual(document.selectedID, annotation.id,
                       "Lo que acabas de dibujar queda listo para ajustarlo")
    }

    func testHitTestFindsShapeByItsOutline() {
        let document = makeDocument()
        _ = addRectangle(to: document)

        // Sobre el borde: sí.
        XCTAssertNotNil(document.annotation(at: CGPoint(x: 100, y: 130), tolerance: 6))
        // En el hueco interior: no, para poder seleccionar lo que haya debajo.
        XCTAssertNil(document.annotation(at: CGPoint(x: 140, y: 130), tolerance: 6))
        // Lejos: no.
        XCTAssertNil(document.annotation(at: CGPoint(x: 10, y: 10), tolerance: 6))
    }

    func testFilledBlurIsGrabbedAnywhere() {
        let document = makeDocument()
        document.add(Annotation(shape: .blur(rect), style: .default))
        XCTAssertNotNil(document.annotation(at: CGPoint(x: 140, y: 130), tolerance: 6),
                        "El blur está relleno: se agarra por cualquier punto")
    }

    func testTopmostAnnotationWins() {
        let document = makeDocument()
        document.add(Annotation(shape: .blur(rect), style: .default))
        let top = Annotation(shape: .blur(rect), style: .default)
        document.add(top)
        XCTAssertEqual(document.annotation(at: CGPoint(x: 140, y: 130), tolerance: 6)?.id, top.id)
    }

    func testCounterAndArrowHitTest() {
        let document = makeDocument()
        document.add(Annotation(shape: .counter(center: CGPoint(x: 200, y: 200), number: 1), style: .default))
        XCTAssertNotNil(document.annotation(at: CGPoint(x: 205, y: 203), tolerance: 4))

        let arrow = Annotation(shape: .arrow(from: CGPoint(x: 20, y: 20), to: CGPoint(x: 120, y: 20)), style: .default)
        document.add(arrow)
        XCTAssertNotNil(document.annotation(at: CGPoint(x: 70, y: 22), tolerance: 6), "Sobre el trazo")
        XCTAssertNil(document.annotation(at: CGPoint(x: 70, y: 90), tolerance: 6), "Lejos del trazo")
    }

    // MARK: - Mover

    func testMovePreservesSizeAndShape() {
        let document = makeDocument()
        let annotation = addRectangle(to: document)
        let moved = annotation.moved(by: CGSize(width: 30, height: -20))

        guard case let .rectangle(newRect) = moved.shape else { return XCTFail("Cambió de tipo") }
        XCTAssertEqual(newRect.origin.x, 130)
        XCTAssertEqual(newRect.origin.y, 80)
        XCTAssertEqual(newRect.size, rect.size, "Mover no cambia el tamaño")
    }

    func testMoveWorksForEveryShape() {
        let delta = CGSize(width: 10, height: 5)
        let shapes: [AnnotationShape] = [
            .rectangle(rect), .ellipse(rect), .blur(rect),
            .arrow(from: .zero, to: CGPoint(x: 50, y: 50)),
            .pencil(points: [CGPoint(x: 1, y: 1), CGPoint(x: 20, y: 20)]),
            .text(origin: CGPoint(x: 5, y: 5), string: "Hola"),
            .counter(center: CGPoint(x: 40, y: 40), number: 2)
        ]
        for shape in shapes {
            let annotation = Annotation(shape: shape, style: .default)
            let moved = annotation.moved(by: delta)
            XCTAssertEqual(moved.localBounds.minX, annotation.localBounds.minX + 10, accuracy: 0.001,
                           "Falló al mover \(shape.tool.rawValue)")
            XCTAssertEqual(moved.localBounds.width, annotation.localBounds.width, accuracy: 0.001)
        }
    }

    /// Un arrastre completo debe contar como una sola operación de deshacer.
    func testDragCountsAsOneUndoStep() {
        let document = makeDocument()
        let annotation = addRectangle(to: document)

        document.beginInteractiveChange()
        for step in 1...20 {
            document.updateLive(annotation.moved(by: CGSize(width: CGFloat(step), height: 0)))
        }
        document.endInteractiveChange()

        document.undo()
        guard case let .rectangle(restored) = document.annotations.first?.shape else {
            return XCTFail("No se restauró")
        }
        XCTAssertEqual(restored, rect, "Un solo deshacer devuelve la anotación a su sitio original")
    }

    func testInteractiveChangeWithoutMovementDoesNotTouchHistory() {
        let document = makeDocument()
        _ = addRectangle(to: document)
        let undoDepthBefore = document.canUndo

        document.beginInteractiveChange()
        document.endInteractiveChange()

        document.undo()
        XCTAssertTrue(undoDepthBefore)
        XCTAssertTrue(document.annotations.isEmpty, "Sólo se deshizo la creación, no un cambio vacío")
    }

    // MARK: - Redimensionar

    func testResizeFromCorner() {
        let annotation = Annotation(shape: .rectangle(rect), style: .default)
        let resized = annotation.resized(handle: .topRight, to: CGPoint(x: 250, y: 220))

        guard case let .rectangle(newRect) = resized.shape else { return XCTFail("Cambió de tipo") }
        XCTAssertEqual(newRect.minX, rect.minX, accuracy: 0.001, "La esquina opuesta no se mueve")
        XCTAssertEqual(newRect.minY, rect.minY, accuracy: 0.001)
        XCTAssertEqual(newRect.maxX, 250, accuracy: 0.001)
        XCTAssertEqual(newRect.maxY, 220, accuracy: 0.001)
    }

    func testResizeNeverCollapses() {
        let annotation = Annotation(shape: .rectangle(rect), style: .default)
        // Se arrastra la esquina muy por detrás de la contraria.
        let resized = annotation.resized(handle: .topRight, to: CGPoint(x: -500, y: -500))
        XCTAssertGreaterThan(resized.localBounds.width, 0)
        XCTAssertGreaterThan(resized.localBounds.height, 0)
    }

    func testArrowEndpointsAreMovable() {
        let annotation = Annotation(shape: .arrow(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 100, y: 10)),
                                    style: .default)
        let resized = annotation.resized(handle: .end, to: CGPoint(x: 10, y: 200))

        guard case let .arrow(from, to) = resized.shape else { return XCTFail("Cambió de tipo") }
        XCTAssertEqual(from, CGPoint(x: 10, y: 10), "El origen no se mueve")
        XCTAssertEqual(to, CGPoint(x: 10, y: 200), "Mover el extremo cambia longitud y orientación")
    }

    func testPencilScalesWithItsBox() {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 0), CGPoint(x: 50, y: 50)]
        let annotation = Annotation(shape: .pencil(points: points), style: .default)
        let originalWidth = annotation.localBounds.width

        let resized = annotation.resized(handle: .topRight, to: CGPoint(x: 200, y: 200))
        XCTAssertGreaterThan(resized.localBounds.width, originalWidth)
        guard case let .pencil(newPoints) = resized.shape else { return XCTFail("Cambió de tipo") }
        XCTAssertEqual(newPoints.count, points.count, "El trazo conserva todos sus puntos")
    }

    func testCounterResizeChangesItsSize() {
        let annotation = Annotation(shape: .counter(center: CGPoint(x: 100, y: 100), number: 3),
                                    style: .default)
        let originalRadius = AnnotationRenderer.counterRadius(for: annotation.style)
        let resized = annotation.resized(handle: .topRight, to: CGPoint(x: 200, y: 200))

        XCTAssertGreaterThan(AnnotationRenderer.counterRadius(for: resized.style), originalRadius)
        XCTAssertEqual(resized.counterNumber, 3, "Cambiar el tamaño no cambia el número")
    }

    func testTextResizeChangesFontSize() {
        let annotation = Annotation(shape: .text(origin: CGPoint(x: 10, y: 10), string: "Hola"),
                                    style: .default)
        let resized = annotation.resized(handle: .topRight, to: CGPoint(x: 300, y: 200))
        XCTAssertGreaterThan(resized.style.fontSize, annotation.style.fontSize)
        XCTAssertEqual(resized.textContent, "Hola")
    }

    // MARK: - Girar

    func testRotationAndHitTestAgree() {
        var annotation = Annotation(shape: .rectangle(CGRect(x: 100, y: 150, width: 200, height: 20)),
                                    style: .default)
        // Un punto sobre el borde superior antes de girar.
        let pointOnEdge = CGPoint(x: 200, y: 170)
        XCTAssertTrue(annotation.hitTest(pointOnEdge, tolerance: 5))

        annotation.rotation = .pi / 2
        XCTAssertFalse(annotation.hitTest(pointOnEdge, tolerance: 5),
                       "Tras girar 90°, ese punto ya no está sobre el borde")

        // El punto equivalente sí lo está: se gira igual alrededor del centro.
        XCTAssertTrue(annotation.hitTest(annotation.toImage(pointOnEdge), tolerance: 5))
    }

    func testRotateTowardsPoint() {
        let annotation = Annotation(shape: .rectangle(rect), style: .default)
        let center = annotation.center
        // Un punto justo a la derecha del centro equivale a girar -90°.
        let rotated = annotation.rotated(towards: CGPoint(x: center.x + 100, y: center.y))
        XCTAssertEqual(rotated.rotation, -.pi / 2, accuracy: 0.0001)
    }

    func testRotationSnapsToFifteenDegrees() {
        let annotation = Annotation(shape: .rectangle(rect), style: .default)
        let center = annotation.center
        let rotated = annotation.rotated(towards: CGPoint(x: center.x + 100, y: center.y + 3), snapping: true)
        let degrees = rotated.rotation * 180 / .pi
        XCTAssertEqual(degrees.truncatingRemainder(dividingBy: 15), 0, accuracy: 0.001)
    }

    func testCountersAndArrowsDoNotOfferRotation() {
        let counter = Annotation(shape: .counter(center: .zero, number: 1), style: .default)
        XCTAssertFalse(counter.canRotate, "Girar un círculo no cambia nada")

        let arrow = Annotation(shape: .arrow(from: .zero, to: CGPoint(x: 10, y: 10)), style: .default)
        XCTAssertFalse(arrow.canRotate, "Una flecha se reorienta moviendo sus extremos")
        XCTAssertNil(arrow.handlePositions()[.rotate])

        let rectangle = Annotation(shape: .rectangle(rect), style: .default)
        XCTAssertTrue(rectangle.canRotate)
        XCTAssertNotNil(rectangle.handlePositions()[.rotate])
    }

    // MARK: - Renumerar contadores

    func testCounterCanBeRenumberedToAnyValue() {
        let document = makeDocument()
        for _ in 1...3 {
            document.add(Annotation(shape: .counter(center: CGPoint(x: 50, y: 50), number: document.nextCounterNumber),
                                    style: .default))
        }
        let fourth = Annotation(shape: .counter(center: CGPoint(x: 90, y: 90), number: document.nextCounterNumber),
                                style: .default)
        document.add(fourth)
        XCTAssertEqual(document.annotations.last?.counterNumber, 4)

        // El usuario decide que ese sea el 8.
        document.setCounterNumber(8, for: fourth.id)
        XCTAssertEqual(document.annotations.last?.counterNumber, 8)

        // Y el siguiente contador continúa desde el mayor existente.
        XCTAssertEqual(document.nextCounterNumber, 9)
    }

    func testRenumberIsUndoable() {
        let document = makeDocument()
        let counter = Annotation(shape: .counter(center: .zero, number: 1), style: .default)
        document.add(counter)

        document.setCounterNumber(42, for: counter.id)
        XCTAssertEqual(document.annotations.first?.counterNumber, 42)

        document.undo()
        XCTAssertEqual(document.annotations.first?.counterNumber, 1)
    }

    func testRenumberIgnoresNonCounters() {
        let document = makeDocument()
        let annotation = addRectangle(to: document)
        document.setCounterNumber(5, for: annotation.id)
        XCTAssertEqual(document.annotations.first?.shape, .rectangle(rect), "No se toca lo que no es contador")
    }

    // MARK: - Borrar y estilo

    func testDeleteSelected() {
        let document = makeDocument()
        let annotation = addRectangle(to: document)
        document.select(annotation.id)
        document.deleteSelected()

        XCTAssertTrue(document.annotations.isEmpty)
        XCTAssertNil(document.selectedID)

        document.undo()
        XCTAssertEqual(document.annotations.count, 1, "Borrar también se deshace")
    }

    func testChangingColorAffectsSelection() {
        let document = makeDocument()
        let annotation = addRectangle(to: document)
        document.select(annotation.id)

        document.color = .green
        document.applyColorToSelection()

        XCTAssertEqual(document.annotations.first?.style.color, .green)
        document.undo()
        XCTAssertEqual(document.annotations.first?.style.color, .red, "El cambio de color se deshace")
    }

    func testBlurIgnoresColourChanges() {
        let document = makeDocument()
        let blur = Annotation(shape: .blur(rect), style: .default)
        document.add(blur)
        document.select(blur.id)

        document.color = .green
        document.applyColorToSelection()
        XCTAssertEqual(document.annotations.first?.style.color, .red, "El blur no pinta con color")
    }

    func testSelectionIsClearedWhenUndoRemovesIt() {
        let document = makeDocument()
        let annotation = addRectangle(to: document)
        document.select(annotation.id)

        document.undo()
        XCTAssertNil(document.selectedID, "No puede quedar seleccionado algo que ya no existe")
    }

    // MARK: - La selección no sale en la imagen

    func testSelectionDoesNotAffectExportedImage() throws {
        let capture = TestSupport.makeCapture(logicalWidth: 200, logicalHeight: 200)
        let document = EditorDocument(capture: capture)
        let annotation = Annotation(shape: .rectangle(rect), style: .default)
        document.add(annotation)

        let withSelection = try ImageExporter.compose(document: document)
        document.select(nil)
        let withoutSelection = try ImageExporter.compose(document: document)

        XCTAssertEqual(TestSupport.differingPixelCount(withSelection, withoutSelection), 0,
                       "El contorno de selección es sólo de pantalla, nunca se exporta")
    }

    func testRotatedAnnotationRendersDifferently() throws {
        let capture = TestSupport.makeCapture(logicalWidth: 200, logicalHeight: 200)
        let straight = Annotation(shape: .rectangle(CGRect(x: 40, y: 90, width: 120, height: 20)), style: .default)
        var turned = straight
        turned.rotation = .pi / 4

        let a = try ImageExporter.compose(capture: capture, annotations: [straight])
        let b = try ImageExporter.compose(capture: capture, annotations: [turned])
        XCTAssertGreaterThan(TestSupport.differingPixelCount(a, b), 100, "El giro se dibuja de verdad")
    }
}
