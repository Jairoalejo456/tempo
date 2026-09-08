import AppKit
import XCTest
@testable import Tempo

/// El texto se reparte en líneas dentro de su caja en lugar de desbordarse.
final class TextLayoutTests: XCTestCase {

    private let longText = "Este es un comentario bastante largo que no cabría de ninguna manera en una sola línea dentro de la captura"

    private func style(width: CGFloat = 200, fontSize: CGFloat = 24) -> AnnotationStyle {
        AnnotationStyle(color: .red, lineWidth: 4, fontSize: fontSize,
                        blurIntensity: AnnotationStyle.defaultBlurIntensity, textWidth: width)
    }

    // MARK: - Reparto en líneas

    func testLongTextWrapsInsteadOfGrowingSideways() {
        let size = AnnotationRenderer.textSize(longText, style: style(width: 200))
        XCTAssertEqual(size.width, 200, "La caja manda: el texto no la desborda")
        XCTAssertGreaterThan(size.height, AnnotationRenderer.lineHeight(for: style()) * 2,
                             "Un texto largo ocupa varias líneas")
    }

    func testNarrowerBoxMeansMoreLines() {
        let wide = AnnotationRenderer.textSize(longText, style: style(width: 400))
        let narrow = AnnotationRenderer.textSize(longText, style: style(width: 150))
        XCTAssertGreaterThan(narrow.height, wide.height,
                             "Estrechar la caja reparte el texto en más líneas")
    }

    func testEmptyTextStillHasOneLine() {
        let size = AnnotationRenderer.textSize("", style: style())
        XCTAssertEqual(size.height, AnnotationRenderer.lineHeight(for: style()), accuracy: 1)
        XCTAssertEqual(size.width, 200, "La caja existe aunque no se haya escrito nada")
    }

    func testTextIsCentredInItsBox() {
        let paragraph = AnnotationRenderer.paragraphStyle()
        XCTAssertEqual(paragraph.alignment, .center)
        XCTAssertEqual(paragraph.lineBreakMode, .byWordWrapping)
    }

    // MARK: - La caja nunca se sale de la captura

    func testWrappedTextFitsInsideTheCapture() throws {
        let capture = TestSupport.makeCapture(logicalWidth: 300, logicalHeight: 200, scale: 2)
        let annotation = Annotation(shape: .text(origin: CGPoint(x: 20, y: 40), string: longText),
                                    style: style(width: 260))

        let bounds = annotation.localBounds
        XCTAssertLessThanOrEqual(bounds.maxX, capture.logicalSize.width,
                                 "El bloque cabe a lo ancho de la captura")

        // Y se dibuja sin reventar la composición.
        let composed = try ImageExporter.compose(capture: capture, annotations: [annotation])
        XCTAssertEqual(composed.width, 600)
    }

    func testBoundsFollowTheBoxWidth() {
        let annotation = Annotation(shape: .text(origin: .zero, string: longText), style: style(width: 180))
        XCTAssertEqual(annotation.localBounds.width, 180, accuracy: 0.5)
    }

    // MARK: - Ajustar la caja

    func testSideHandleChangesTheWidthNotTheFontSize() {
        let annotation = Annotation(shape: .text(origin: CGPoint(x: 50, y: 50), string: longText),
                                    style: style(width: 200))
        let widened = annotation.resized(handle: .right, to: CGPoint(x: 380, y: 50))

        XCTAssertEqual(widened.style.textWidth, 330, accuracy: 1)
        XCTAssertEqual(widened.style.fontSize, annotation.style.fontSize,
                       "Los lados sólo cambian la anchura")
        XCTAssertLessThan(widened.localBounds.height, annotation.localBounds.height,
                          "Al ensanchar, el texto cabe en menos líneas")
    }

    func testWidthNeverCollapses() {
        let annotation = Annotation(shape: .text(origin: CGPoint(x: 50, y: 50), string: "Hola"),
                                    style: style(width: 200))
        let squashed = annotation.resized(handle: .right, to: CGPoint(x: -500, y: 50))
        XCTAssertGreaterThanOrEqual(squashed.style.textWidth, AnnotationStyle.minimumTextWidth)
    }

    func testCornerHandleChangesTheFontSize() {
        let annotation = Annotation(shape: .text(origin: CGPoint(x: 50, y: 50), string: "Hola"),
                                    style: style(width: 200, fontSize: 24))
        let bigger = annotation.resized(handle: .topRight, to: CGPoint(x: 300, y: 300))
        XCTAssertGreaterThan(bigger.style.fontSize, 24)
    }

    func testLeftHandleKeepsTheRightEdgeStill() {
        let annotation = Annotation(shape: .text(origin: CGPoint(x: 100, y: 50), string: "Hola"),
                                    style: style(width: 200))
        let rightEdge = annotation.localBounds.maxX

        let resized = annotation.resized(handle: .left, to: CGPoint(x: 160, y: 50))
        XCTAssertEqual(resized.localBounds.maxX, rightEdge, accuracy: 1,
                       "Arrastrar por la izquierda no mueve el borde derecho")
    }

    func testTextOffersSideHandles() {
        let annotation = Annotation(shape: .text(origin: .zero, string: "Hola"), style: style())
        let handles = annotation.handlePositions()
        XCTAssertNotNil(handles[.left])
        XCTAssertNotNil(handles[.right])
        XCTAssertNotNil(handles[.topLeft])
        XCTAssertNil(handles[.top], "Arriba y abajo no aportan nada: el alto lo decide el texto")
    }

    // MARK: - El estilo viaja con la selección

    func testSelectingATextAdoptsItsWidth() {
        let document = EditorDocument(capture: TestSupport.makeCapture())
        document.textWidth = 320
        document.add(Annotation(shape: .text(origin: .zero, string: "Hola"), style: style(width: 150)))
        XCTAssertEqual(document.textWidth, 150,
                       "La caja del siguiente texto parte de la del que acabas de tocar")
    }

    func testMovingATextKeepsItsBox() {
        let annotation = Annotation(shape: .text(origin: CGPoint(x: 10, y: 10), string: longText),
                                    style: style(width: 200))
        let moved = annotation.moved(by: CGSize(width: 40, height: 25))
        XCTAssertEqual(moved.style.textWidth, 200)
        XCTAssertEqual(moved.localBounds.height, annotation.localBounds.height, accuracy: 0.5)
    }
}
