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

    func testToolbarStartsWithThePointerAndEndsWithCrop() {
        XCTAssertEqual(EditorTool.allCases.first, .navigate)
        XCTAssertEqual(EditorTool.allCases.last, .crop,
                       "Recortar va al final: no dibuja, cambia el encuadre")
        // Puntero + herramientas de dibujo + recorte.
        XCTAssertEqual(EditorTool.allCases.count, AnnotationTool.allCases.count + 2)
    }

    func testCropIsNotAnAnnotationTool() {
        XCTAssertNil(EditorTool.crop.annotationTool)
        XCTAssertFalse(EditorTool.crop.usesColor, "Recortar no pinta nada")
        XCTAssertEqual(EditorTool.crop.shortcutKey, "k")
    }

    func testColorPaletteStaysAvailableWithThePointer() {
        XCTAssertTrue(EditorTool.navigate.usesColor,
                      "Con el puntero se puede dejar preparado el color de la siguiente anotación")
        XCTAssertTrue(EditorTool.annotate(.arrow).usesColor)
        XCTAssertFalse(EditorTool.annotate(.blur).usesColor, "El blur es la única que no pinta con color")
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
