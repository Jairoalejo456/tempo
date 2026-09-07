import AppKit
import Combine
import Foundation

/// Ajustes de la aplicación, guardados en `UserDefaults`.
///
/// Todo es local: no hay cuentas, ni sincronización, ni telemetría.
final class Preferences: ObservableObject {

    static let shared = Preferences()

    /// Qué ocurre al pulsar Guardar.
    enum SaveMode: String, CaseIterable, Identifiable, Codable {
        /// Abre el panel de macOS para elegir carpeta y nombre.
        case ask
        /// Guarda directamente en la carpeta configurada, sin preguntar.
        case direct

        var id: String { rawValue }

        var title: String {
            switch self {
            case .ask: return "Preguntar dónde guardar"
            case .direct: return "Guardar directamente en la carpeta"
            }
        }

        var explanation: String {
            switch self {
            case .ask: return "Se abre el panel de macOS para elegir carpeta y nombre."
            case .direct: return "La captura se guarda al instante con un nombre con fecha y hora."
            }
        }
    }

    private enum Key {
        static let fullScreenShortcut = "shortcut.fullScreen"
        static let regionShortcut = "shortcut.region"
        static let saveMode = "save.mode"
        static let saveFolder = "save.folder"
        static let showsDockIcon = "appearance.showsDockIcon"
        static let hasLaunchedBefore = "app.hasLaunchedBefore"
    }

    private let defaults: UserDefaults

    // MARK: - Ajustes

    @Published var fullScreenShortcut: GlobalShortcut {
        didSet { store(fullScreenShortcut, for: Key.fullScreenShortcut) }
    }

    @Published var regionShortcut: GlobalShortcut {
        didSet { store(regionShortcut, for: Key.regionShortcut) }
    }

    @Published var saveMode: SaveMode {
        didSet { defaults.set(saveMode.rawValue, forKey: Key.saveMode) }
    }

    /// Carpeta de destino cuando se guarda sin preguntar.
    @Published var saveFolder: URL {
        didSet { defaults.set(saveFolder.path, forKey: Key.saveFolder) }
    }

    /// Si está activo, Tempo se comporta como una aplicación normal: icono permanente en el
    /// Dock y en el conmutador de aplicaciones. Desactivado, vive solo en la barra de menús.
    @Published var showsDockIcon: Bool {
        didSet { defaults.set(showsDockIcon, forKey: Key.showsDockIcon) }
    }

    // MARK: - Ciclo de vida

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        fullScreenShortcut = Preferences.load(from: defaults, key: Key.fullScreenShortcut) ?? .defaultFullScreen
        regionShortcut = Preferences.load(from: defaults, key: Key.regionShortcut) ?? .defaultRegion
        saveMode = (defaults.string(forKey: Key.saveMode).flatMap(SaveMode.init(rawValue:))) ?? .ask
        showsDockIcon = defaults.bool(forKey: Key.showsDockIcon)

        if let path = defaults.string(forKey: Key.saveFolder) {
            saveFolder = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            saveFolder = Preferences.defaultSaveFolder
        }
    }

    /// `true` sólo la primera vez que se abre la aplicación en este Mac. Se usa para enseñar
    /// los ajustes en el primer arranque, en lugar de dejar al usuario sin ninguna señal.
    func consumeFirstLaunchFlag() -> Bool {
        guard !defaults.bool(forKey: Key.hasLaunchedBefore) else { return false }
        defaults.set(true, forKey: Key.hasLaunchedBefore)
        return true
    }

    static var defaultSaveFolder: URL {
        FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
    }

    /// Restablece los atajos a los valores de fábrica.
    func resetShortcuts() {
        fullScreenShortcut = .defaultFullScreen
        regionShortcut = .defaultRegion
    }

    /// La carpeta elegida podría haberse borrado o movido desde la última vez.
    var saveFolderExists: Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: saveFolder.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    // MARK: - Persistencia

    private func store(_ shortcut: GlobalShortcut, for key: String) {
        guard let data = try? JSONEncoder().encode(shortcut) else { return }
        defaults.set(data, forKey: key)
    }

    private static func load(from defaults: UserDefaults, key: String) -> GlobalShortcut? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(GlobalShortcut.self, from: data)
    }

    // MARK: - Información de la aplicación

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    static var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Tempo"
    }
}
