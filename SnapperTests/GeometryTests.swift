import AppKit
import XCTest
@testable import Snapper

/// Conversión de coordenadas entre AppKit (origen abajo‑izquierda) y ScreenCaptureKit
/// (origen arriba‑izquierda), y colocación de la miniatura.
final class GeometryTests: XCTestCase {

    /// Pantalla ficticia para no depender del hardware real.
    private func makeScreenLikeRect(origin: CGPoint, size: CGSize) -> CGRect {
        CGRect(origin: origin, size: size)
    }

    func testSourceRectConversionOnPrimaryScreen() {
        // Pantalla principal: origen (0,0), 1000×800. Región de 100×50 con esquina inferior
        // izquierda en (200, 600) ⇒ arriba‑izquierda queda a 800 − 650 = 150 del borde superior.
        let screenFrame = makeScreenLikeRect(origin: .zero, size: CGSize(width: 1000, height: 800))
        let region = CGRect(x: 200, y: 600, width: 100, height: 50)

        let converted = CGRect(x: region.minX - screenFrame.minX,
                               y: screenFrame.maxY - region.maxY,
                               width: region.width,
                               height: region.height)

        XCTAssertEqual(converted, CGRect(x: 200, y: 150, width: 100, height: 50))
    }

    func testSourceRectConversionOnSecondaryScreen() {
        // Monitor secundario a la derecha, con origen en x = 1000.
        let screenFrame = makeScreenLikeRect(origin: CGPoint(x: 1000, y: 0), size: CGSize(width: 1440, height: 900))
        let region = CGRect(x: 1100, y: 700, width: 200, height: 100)

        let converted = CGRect(x: region.minX - screenFrame.minX,
                               y: screenFrame.maxY - region.maxY,
                               width: region.width,
                               height: region.height)

        XCTAssertEqual(converted, CGRect(x: 100, y: 100, width: 200, height: 100),
                       "La región se expresa relativa a su propio monitor")
    }

    /// Comprueba la implementación real contra una pantalla del sistema.
    func testSourceRectMatchesImplementation() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let frame = screen.frame
        let region = CGRect(x: frame.minX + 50, y: frame.minY + 60, width: 120, height: 80)

        let result = ScreenCaptureService.sourceRect(for: region, in: screen)

        XCTAssertEqual(result.width, 120)
        XCTAssertEqual(result.height, 80)
        XCTAssertEqual(result.minX, 50, accuracy: 0.001)
        XCTAssertEqual(result.minY, frame.height - 60 - 80, accuracy: 0.001)
    }

    // MARK: - Miniatura

    func testThumbnailKeepsAspectRatio() {
        let wide = ThumbnailWindowController.fittedSize(for: CGSize(width: 1600, height: 400))
        XCTAssertLessThanOrEqual(wide.width, 208)
        XCTAssertLessThanOrEqual(wide.height, 168)
        XCTAssertEqual(wide.width / wide.height, 4, accuracy: 0.35)

        let tall = ThumbnailWindowController.fittedSize(for: CGSize(width: 300, height: 1200))
        XCTAssertLessThanOrEqual(tall.height, 168)
    }

    func testThumbnailHasMinimumSizeForTinyCaptures() {
        let tiny = ThumbnailWindowController.fittedSize(for: CGSize(width: 12, height: 8))
        XCTAssertGreaterThanOrEqual(tiny.width, 72)
        XCTAssertGreaterThanOrEqual(tiny.height, 72)
    }

    func testThumbnailHandlesDegenerateSize() {
        let size = ThumbnailWindowController.fittedSize(for: .zero)
        XCTAssertGreaterThan(size.width, 0)
        XCTAssertGreaterThan(size.height, 0)
    }

    // MARK: - Atajos

    func testToolShortcutsAreUniqueAndPresent() {
        let keys = AnnotationTool.allCases.map(\.shortcutKey)
        XCTAssertEqual(Set(keys).count, keys.count, "Ninguna tecla puede estar repetida")
        XCTAssertEqual(Set(keys), ["a", "r", "o", "t", "p", "b", "c"])
    }

    func testGlobalShortcutsAreDistinct() {
        XCTAssertNotEqual(HotKeyManager.fullScreenShortcut.keyCode, HotKeyManager.regionShortcut.keyCode)
        XCTAssertFalse(HotKeyManager.fullScreenShortcut.display.isEmpty)
        XCTAssertFalse(HotKeyManager.regionShortcut.display.isEmpty)
    }

    func testPaletteHasEightColorsForKeys1To8() {
        XCTAssertEqual(AnnotationColor.palette.count, 8)
        XCTAssertEqual(Set(AnnotationColor.palette).count, 8, "Sin colores duplicados")
    }
}
