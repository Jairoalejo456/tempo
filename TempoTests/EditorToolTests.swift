import XCTest
@testable import Tempo

/// Modo del editor: el puntero navega, el resto dibuja.
final class EditorToolTests: XCTestCase {

    func testEditorOpensInPointerMode() {
        let document = EditorDocument(capture: TestSupport.makeCapture())
        XCTAssertEqual(document.tool, .navigate,
                       "Al abrir el editor no debe haber ninguna herramienta de dibujo activa")
        XCTAssertNil(document.tool.annotationTool)
    }

    func testPointerHasNoAnnotationTool() {
        XCTAssertNil(EditorTool.navigate.annotationTool)
        XCTAssertEqual(EditorTool.annotate(.arrow).annotationTool, .arrow)
    }

    func testAllToolsHaveUniqueShortcuts() {
        let keys = EditorTool.allCases.map(\.shortcutKey)
        XCTAssertEqual(Set(keys).count, keys.count, "Ninguna tecla puede estar repetida")
        XCTAssertEqual(EditorTool.navigate.shortcutKey, "v")
    }

    func testPointerIsFirstInTheToolbar() {
        XCTAssertEqual(EditorTool.allCases.first, .navigate)
        XCTAssertEqual(EditorTool.allCases.count, AnnotationTool.allCases.count + 1)
    }

    func testPointerDoesNotUseColor() {
        XCTAssertFalse(EditorTool.navigate.usesColor)
        XCTAssertTrue(EditorTool.annotate(.arrow).usesColor)
        XCTAssertFalse(EditorTool.annotate(.blur).usesColor, "El blur no pinta con color")
    }

    func testZoomStateStartsFitted() {
        let document = EditorDocument(capture: TestSupport.makeCapture())
        XCTAssertEqual(document.zoomFactor, 1)
        XCTAssertEqual(document.fitScale, 1)
        XCTAssertEqual(document.effectiveZoom, 1)
    }

    func testEffectiveZoomCombinesFitAndUserZoom() {
        let document = EditorDocument(capture: TestSupport.makeCapture())
        document.fitScale = 0.5
        document.zoomFactor = 2
        XCTAssertEqual(document.effectiveZoom, 1, accuracy: 0.0001,
                       "Ajustada al 50 % y con el doble de zoom, se ve a tamaño real")
    }
}
