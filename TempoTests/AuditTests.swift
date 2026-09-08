import AppKit
import XCTest
@testable import Tempo

/// Comprobaciones de coherencia de la aplicación en conjunto.
///
/// No prueban una función concreta, sino que lo prometido y lo implementado siguen coincidiendo:
/// es lo que se desincroniza en silencio cuando se añade una herramienta o se cambia un atajo.
final class AuditTests: XCTestCase {

    // MARK: - Herramientas

    func testEveryToolHasNameSymbolAndShortcut() {
        for tool in EditorTool.allCases {
            XCTAssertFalse(tool.title.isEmpty, "\(tool.id) sin nombre visible")
            XCTAssertFalse(tool.symbolName.isEmpty, "\(tool.id) sin icono")
            XCTAssertEqual(tool.shortcutKey.count, 1, "\(tool.id) debe tener una tecla única")
            XCTAssertNotNil(NSImage(systemSymbolName: tool.symbolName, accessibilityDescription: nil),
                            "El icono «\(tool.symbolName)» de \(tool.id) no existe en el sistema")
        }
    }

    func testToolShortcutsDoNotCollide() {
        let keys = EditorTool.allCases.map(\.shortcutKey)
        XCTAssertEqual(Set(keys).count, keys.count, "Hay teclas de herramienta repetidas: \(keys)")
    }

    /// Las teclas de herramienta no pueden ser dígitos: esos están tomados por los colores y,
    /// con un contador elegido, por su número.
    func testToolShortcutsAreNotDigits() {
        for tool in EditorTool.allCases {
            XCTAssertFalse(tool.shortcutKey.first?.isNumber ?? false,
                           "\(tool.id) usa un dígito, que ya es atajo de color")
        }
    }

    func testColourShortcutsCoverThePalette() {
        // Los colores se eligen con 1…8, así que la paleta no puede crecer sin más.
        XCTAssertLessThanOrEqual(AnnotationColor.palette.count, 9,
                                 "Con más de nueve colores dejaría de haber teclas para todos")
    }

    // MARK: - Atajos globales

    func testDefaultGlobalShortcutsAreValidAndDistinct() {
        let shortcuts = [GlobalShortcut.defaultFullScreen, .defaultRegion]
        for shortcut in shortcuts {
            XCTAssertTrue(shortcut.isValid, "\(shortcut.display) necesita ⌘, ⌥ o ⌃")
            XCTAssertFalse(shortcut.display.isEmpty)
        }
        XCTAssertEqual(Set(shortcuts.map(\.display)).count, shortcuts.count)
    }

    /// No deben chocar con los atajos de captura del propio macOS (⇧⌘3, ⇧⌘4, ⇧⌘5).
    func testGlobalShortcutsDoNotClashWithMacOSCapture() {
        let systemCombinations: Set<String> = ["⇧⌘3", "⇧⌘4", "⇧⌘5", "⌃⇧⌘3", "⌃⇧⌘4"]
        for shortcut in [GlobalShortcut.defaultFullScreen, .defaultRegion] {
            XCTAssertFalse(systemCombinations.contains(shortcut.display),
                           "\(shortcut.display) ya lo usa macOS")
        }
    }

    // MARK: - Ajustes

    func testEverySettingHasAReadableTitle() {
        for mode in Preferences.SaveMode.allCases {
            XCTAssertFalse(mode.title.isEmpty)
            XCTAssertFalse(mode.explanation.isEmpty)
        }
        for size in Preferences.CopySize.allCases {
            XCTAssertFalse(size.title.isEmpty)
        }
        for action in HotKeyManager.Action.allCases {
            XCTAssertFalse(action.title.isEmpty)
        }
    }

    func testDefaultsAreSensible() throws {
        let suite = "com.jairo.tempo.tests.audit.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let preferences = Preferences(defaults: defaults)

        XCTAssertEqual(preferences.saveMode, .ask, "Guardar pregunta por omisión")
        XCTAssertTrue(preferences.dismissesAfterDrag)
        XCTAssertTrue(preferences.keepsHistory)
        XCTAssertFalse(preferences.showsDockIcon, "Es una utilidad de barra de menús")
        XCTAssertTrue(Preferences.historyDayOptions.contains(preferences.historyDays))
        XCTAssertNotNil(preferences.copySize.maximumSide, "Al copiar se reduce por omisión")
    }

    // MARK: - Identidad

    func testBundleIdentityIsComplete() {
        XCTAssertEqual(Preferences.appName, "Tempo")
        XCTAssertFalse(Preferences.appVersion.isEmpty)
        XCTAssertFalse(Preferences.buildNumber.isEmpty)
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.jairo.tempo")
    }

    func testAppIconIsBundled() {
        XCTAssertNotNil(NSImage(named: "MenuBarIcon"), "Falta el icono de la barra de menús")
        XCTAssertNotNil(Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
                        "Falta el icono de la aplicación")
    }

    // MARK: - Recorrido completo, de la captura a la salida

    /// Reproduce el flujo entero sobre una captura sintética: anotar con todas las herramientas,
    /// recortar, deshacer, rehacer, componer y copiar.
    func testFullEditingRoundTrip() throws {
        let capture = TestSupport.makeCapture(logicalWidth: 400, logicalHeight: 300, scale: 2)
        let document = EditorDocument(capture: capture)

        for tool in AnnotationTool.allCases {
            document.tool = .annotate(tool)
            let shape: AnnotationShape
            switch tool {
            case .arrow: shape = .arrow(from: CGPoint(x: 20, y: 20), to: CGPoint(x: 120, y: 90))
            case .rectangle: shape = .rectangle(CGRect(x: 30, y: 30, width: 80, height: 60))
            case .ellipse: shape = .ellipse(CGRect(x: 140, y: 30, width: 80, height: 60))
            case .pencil: shape = .pencil(points: [CGPoint(x: 20, y: 200), CGPoint(x: 90, y: 240)])
            case .blur: shape = .blur(CGRect(x: 240, y: 30, width: 90, height: 70))
            case .text: shape = .text(origin: CGPoint(x: 30, y: 150), string: "Revisar")
            case .counter: shape = .counter(center: CGPoint(x: 320, y: 200), number: document.nextCounterNumber)
            }
            document.place(Annotation(shape: shape, style: document.currentStyle))
            XCTAssertEqual(document.tool, .navigate, "Tras colocar \(tool.rawValue) vuelve el puntero")
        }
        XCTAssertEqual(document.annotations.count, AnnotationTool.allCases.count)

        // Recortar conserva lo que queda dentro y se puede deshacer.
        let beforeCrop = document.annotations.count
        document.crop(to: CGRect(x: 10, y: 10, width: 360, height: 260))
        let afterCrop = document.annotations.count
        XCTAssertLessThanOrEqual(afterCrop, beforeCrop)
        XCTAssertEqual(document.capture.logicalSize, CGSize(width: 360, height: 260))

        document.undo()
        XCTAssertEqual(document.annotations.count, beforeCrop)
        XCTAssertEqual(document.capture.logicalSize, CGSize(width: 400, height: 300),
                       "Deshacer un recorte devuelve los píxeles que se habían quitado")

        // Deshacer hasta vaciar y rehacer hasta el final. Rehacer del todo incluye el recorte,
        // así que el documento vuelve al estado de después de recortar, no al de antes.
        var guardRail = 0
        while document.canUndo, guardRail < 100 { document.undo(); guardRail += 1 }
        XCTAssertTrue(document.annotations.isEmpty)
        XCTAssertEqual(document.capture.logicalSize, CGSize(width: 400, height: 300))

        while document.canRedo, guardRail < 200 { document.redo(); guardRail += 1 }
        XCTAssertEqual(document.annotations.count, afterCrop)
        XCTAssertEqual(document.capture.logicalSize, CGSize(width: 360, height: 260))

        // Y la salida final corresponde exactamente a la captura que hay en ese momento.
        let composed = try ImageExporter.compose(document: document)
        XCTAssertEqual(CGFloat(composed.width), document.capture.pixelSize.width)
        XCTAssertEqual(CGFloat(composed.height), document.capture.pixelSize.height)
        try ImageExporter.copyToPasteboard(image: composed, maximumSide: 1600)
        XCTAssertNotNil(NSPasteboard.general.data(forType: .png))
    }

    // MARK: - Regresiones

    /// El archivo que se arrastra debe rehacerse cuando cambia la captura, no sólo cuando
    /// cambian las anotaciones: recortar una captura sin anotar dejaba en caché el archivo
    /// anterior y se arrastraba la imagen sin recortar.
    func testDocumentSnapshotDetectsACropWithoutAnnotations() {
        let document = EditorDocument(capture: TestSupport.makeCapture(logicalWidth: 200, logicalHeight: 200))
        let before = document.snapshot
        XCTAssertTrue(document.annotations.isEmpty)

        document.crop(to: CGRect(x: 10, y: 10, width: 120, height: 120))

        XCTAssertNotEqual(before, document.snapshot,
                          "Sin esto, el archivo de arrastre se reutilizaría con la imagen vieja")
        XCTAssertEqual(before.annotations, document.snapshot.annotations,
                       "Y las anotaciones no han cambiado: la diferencia está en la captura")
    }

    /// Recortar puede cambiar la proporción de la captura, y la miniatura tiene que seguirla o
    /// mostraría la imagen deformada.
    func testThumbnailSizeFollowsTheAspectRatio() {
        let wide = ThumbnailWindowController.fittedSize(for: CGSize(width: 400, height: 200))
        let square = ThumbnailWindowController.fittedSize(for: CGSize(width: 300, height: 300))

        XCTAssertEqual(wide.width / wide.height, 2, accuracy: 0.05)
        XCTAssertEqual(square.width / square.height, 1, accuracy: 0.05)
        XCTAssertNotEqual(wide, square, "Cada proporción tiene su propio tamaño de panel")
    }

    // MARK: - Casos límite

    func testCancellingActionsLeavesEverythingIntact() {
        let document = EditorDocument(capture: TestSupport.makeCapture())

        // Un gesto que no llega a dibujar nada no ensucia el documento ni el historial.
        document.tool = .annotate(.rectangle)
        document.place(Annotation(shape: .rectangle(CGRect(x: 5, y: 5, width: 0, height: 0)),
                                  style: .default))
        XCTAssertTrue(document.annotations.isEmpty)
        XCTAssertFalse(document.canUndo)
        XCTAssertEqual(document.tool, .annotate(.rectangle), "La herramienta sigue elegida")

        // Un recorte vacío se rechaza sin dejar rastro.
        XCTAssertFalse(document.crop(to: .zero))
        XCTAssertFalse(document.canUndo)
    }

    func testUndoAndRedoOnAnUntouchedDocumentDoNothing() {
        let document = EditorDocument(capture: TestSupport.makeCapture())
        document.undo()
        document.redo()
        XCTAssertTrue(document.annotations.isEmpty)
        XCTAssertNil(document.selectedID)
    }

    func testDeletingWithoutSelectionIsHarmless() {
        let document = EditorDocument(capture: TestSupport.makeCapture())
        document.deleteSelected()
        XCTAssertTrue(document.annotations.isEmpty)
    }

    /// Ninguna herramienta puede dejar el documento en un estado imposible.
    func testNoToolProducesAnInvalidDocument() {
        let document = EditorDocument(capture: TestSupport.makeCapture())
        for tool in EditorTool.allCases {
            document.tool = tool
            XCTAssertNotNil(document.currentStyle)
            XCTAssertGreaterThan(document.currentStyle.lineWidth, 0)
            XCTAssertGreaterThan(document.currentStyle.fontSize, 0)
            XCTAssertTrue((0...1).contains(document.currentStyle.blurIntensity))
            XCTAssertGreaterThanOrEqual(document.currentStyle.textWidth, AnnotationStyle.minimumTextWidth)
        }
    }
}
