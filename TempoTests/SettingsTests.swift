import AppKit
import Carbon.HIToolbox
import XCTest
@testable import Tempo

/// Atajos configurables y ajustes persistentes.
final class SettingsTests: XCTestCase {

    // MARK: - Atajos

    func testShortcutRequiresACommandModifier() {
        let plain = GlobalShortcut(keyCode: kVK_ANSI_S, modifiers: [])
        XCTAssertFalse(plain.isValid, "Un atajo global sin modificadores secuestraría una tecla normal")

        let onlyShift = GlobalShortcut(keyCode: kVK_ANSI_S, modifiers: [.shift])
        XCTAssertFalse(onlyShift.isValid, "Mayúsculas sola tampoco basta")

        XCTAssertTrue(GlobalShortcut(keyCode: kVK_ANSI_S, modifiers: [.command]).isValid)
        XCTAssertTrue(GlobalShortcut(keyCode: kVK_ANSI_S, modifiers: [.option]).isValid)
        XCTAssertTrue(GlobalShortcut(keyCode: kVK_ANSI_S, modifiers: [.control]).isValid)
    }

    func testShortcutDisplayUsesMacOSOrder() {
        let shortcut = GlobalShortcut(keyCode: kVK_ANSI_S, modifiers: [.command, .shift, .option, .control])
        // macOS siempre los ordena ⌃ ⌥ ⇧ ⌘.
        XCTAssertTrue(shortcut.display.hasPrefix("⌃⌥⇧⌘"), "Obtenido: \(shortcut.display)")
    }

    func testDefaultShortcutsAreValidAndDistinct() {
        XCTAssertTrue(GlobalShortcut.defaultFullScreen.isValid)
        XCTAssertTrue(GlobalShortcut.defaultRegion.isValid)
        XCTAssertNotEqual(GlobalShortcut.defaultFullScreen, GlobalShortcut.defaultRegion)
        XCTAssertEqual(GlobalShortcut.defaultFullScreen.display, "⌥⇧⌘F")
        XCTAssertEqual(GlobalShortcut.defaultRegion.display, "⌥⇧⌘S")
    }

    func testSpecialKeyNames() {
        XCTAssertEqual(GlobalShortcut(keyCode: kVK_Space, modifiers: [.command]).display, "⌘Espacio")
        XCTAssertEqual(GlobalShortcut(keyCode: kVK_F5, modifiers: [.control]).display, "⌃F5")
    }

    func testCarbonModifiersConversion() {
        let shortcut = GlobalShortcut(keyCode: kVK_ANSI_A, modifiers: [.command, .option])
        let carbon = shortcut.carbonModifiers
        XCTAssertEqual(carbon & UInt32(cmdKey), UInt32(cmdKey))
        XCTAssertEqual(carbon & UInt32(optionKey), UInt32(optionKey))
        XCTAssertEqual(carbon & UInt32(shiftKey), 0)
        XCTAssertEqual(carbon & UInt32(controlKey), 0)
    }

    func testShortcutRoundTripsThroughStorage() throws {
        let original = GlobalShortcut(keyCode: kVK_ANSI_K, modifiers: [.command, .control])
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(GlobalShortcut.self, from: data)
        XCTAssertEqual(original, restored)
    }

    // MARK: - Preferencias

    private func makeIsolatedPreferences() throws -> (Preferences, UserDefaults, String) {
        let suite = "com.jairo.tempo.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        return (Preferences(defaults: defaults), defaults, suite)
    }

    func testPreferencesDefaults() throws {
        let (preferences, _, suite) = try makeIsolatedPreferences()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        XCTAssertEqual(preferences.fullScreenShortcut, .defaultFullScreen)
        XCTAssertEqual(preferences.regionShortcut, .defaultRegion)
        XCTAssertEqual(preferences.saveMode, .ask, "Por omisión se pregunta dónde guardar")
        XCTAssertFalse(preferences.saveFolder.path.isEmpty)
    }

    func testPreferencesPersistAcrossInstances() throws {
        let (preferences, defaults, suite) = try makeIsolatedPreferences()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        let custom = GlobalShortcut(keyCode: kVK_ANSI_1, modifiers: [.command, .control])
        preferences.fullScreenShortcut = custom
        preferences.saveMode = .direct
        preferences.saveFolder = FileManager.default.temporaryDirectory

        let reloaded = Preferences(defaults: defaults)
        XCTAssertEqual(reloaded.fullScreenShortcut, custom)
        XCTAssertEqual(reloaded.saveMode, .direct)
        XCTAssertEqual(reloaded.saveFolder.standardizedFileURL,
                       FileManager.default.temporaryDirectory.standardizedFileURL)
    }

    func testResetShortcuts() throws {
        let (preferences, _, suite) = try makeIsolatedPreferences()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        preferences.fullScreenShortcut = GlobalShortcut(keyCode: kVK_ANSI_9, modifiers: [.command])
        preferences.resetShortcuts()
        XCTAssertEqual(preferences.fullScreenShortcut, .defaultFullScreen)
        XCTAssertEqual(preferences.regionShortcut, .defaultRegion)
    }

    func testMissingSaveFolderIsDetected() throws {
        let (preferences, _, suite) = try makeIsolatedPreferences()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        preferences.saveFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("carpeta-que-no-existe-\(UUID().uuidString)")
        XCTAssertFalse(preferences.saveFolderExists, "Si la carpeta desapareció, los ajustes lo advierten")
    }

    // MARK: - Identidad de la aplicación

    func testAppNameIsUsedForWindowTitles() {
        // El título de la ventana del editor sale de aquí, para que se reconozca la aplicación.
        XCTAssertEqual(Preferences.appName, "Tempo")
        XCTAssertFalse(Preferences.appVersion.isEmpty)
        XCTAssertFalse(Preferences.buildNumber.isEmpty)
    }

    // MARK: - Presencia en el sistema

    func testDockIconIsOffByDefault() throws {
        let (preferences, _, suite) = try makeIsolatedPreferences()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        XCTAssertFalse(preferences.showsDockIcon,
                       "Por omisión Tempo es una utilidad de barra de menús")
    }

    func testDockIconPreferencePersists() throws {
        let (preferences, defaults, suite) = try makeIsolatedPreferences()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        preferences.showsDockIcon = true
        XCTAssertTrue(Preferences(defaults: defaults).showsDockIcon)
    }

    func testFirstLaunchFlagIsConsumedOnce() throws {
        let (preferences, defaults, suite) = try makeIsolatedPreferences()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        XCTAssertTrue(preferences.consumeFirstLaunchFlag(), "La primera vez sí")
        XCTAssertFalse(preferences.consumeFirstLaunchFlag(), "La segunda ya no")
        XCTAssertFalse(Preferences(defaults: defaults).consumeFirstLaunchFlag(),
                       "Tampoco en arranques posteriores")
    }

    // MARK: - Guardado directo

    func testAvailableURLNeverOverwrites() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("tempo-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let first = ImageExporter.availableURL(for: "Captura.png", in: folder)
        XCTAssertEqual(first.lastPathComponent, "Captura.png")
        try Data("x".utf8).write(to: first)

        let second = ImageExporter.availableURL(for: "Captura.png", in: folder)
        XCTAssertEqual(second.lastPathComponent, "Captura (2).png")
        try Data("x".utf8).write(to: second)

        let third = ImageExporter.availableURL(for: "Captura.png", in: folder)
        XCTAssertEqual(third.lastPathComponent, "Captura (3).png")
    }
}
