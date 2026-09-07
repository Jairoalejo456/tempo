import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private var preferencesController: PreferencesWindowController?
    private var cancellables: Set<AnyCancellable> = []

    /// Bajo XCTest la aplicación se carga como host de las pruebas: no debe registrar atajos
    /// globales ni mostrar interfaz.
    private var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !isRunningTests else { return }

        ImageExporter.cleanTemporaryFiles()
        NSApp.mainMenu = MainMenu.build()
        setUpStatusItem()
        setUpHotKeys()

        // Modo demo: abre una captura de ejemplo para probar el editor sin permisos.
        if CommandLine.arguments.contains("--demo") {
            DispatchQueue.main.async {
                AppCoordinator.shared.presentDemoCapture()
            }
            return
        }

        // Al arrancar por primera vez se pide el permiso para que el primer atajo ya funcione.
        if !ScreenCaptureService.hasPermission {
            ScreenCaptureService.requestPermission()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotKeyManager.shared.unregisterAll()
        ImageExporter.cleanTemporaryFiles()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Es una utilidad de barra de menús: sigue viva aunque no haya ventanas.
        false
    }

    // MARK: - Atajos globales

    private func setUpHotKeys() {
        HotKeyManager.shared.handler = { action in
            switch action {
            case .captureFullScreen: AppCoordinator.shared.captureFullScreen()
            case .captureRegion: AppCoordinator.shared.captureRegion()
            }
        }
        reloadHotKeys()

        // Cambiar un atajo en los ajustes lo aplica al instante, sin reiniciar.
        let preferences = Preferences.shared
        preferences.$fullScreenShortcut
            .combineLatest(preferences.$regionShortcut)
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reloadHotKeys() }
            .store(in: &cancellables)
    }

    private func reloadHotKeys() {
        let failed = HotKeyManager.shared.reload(with: Preferences.shared)
        if !failed.isEmpty {
            let names = failed.map(\.title).joined(separator: ", ")
            NSLog("[Tempo] Atajos no registrados (¿ocupados por otra aplicación?): \(names)")
        }
    }

    // MARK: - Barra de menús

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(named: "MenuBarIcon") ?? NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Tempo")
        item.button?.image?.isTemplate = true

        let menu = NSMenu()

        let full = menu.addItem(withTitle: HotKeyManager.Action.captureFullScreen.title,
                                action: #selector(captureFullScreen(_:)),
                                keyEquivalent: "")
        full.target = self
        full.tag = 1

        let region = menu.addItem(withTitle: HotKeyManager.Action.captureRegion.title + "…",
                                  action: #selector(captureRegion(_:)),
                                  keyEquivalent: "")
        region.target = self
        region.tag = 2

        menu.addItem(.separator())

        let settings = menu.addItem(withTitle: "Ajustes…", action: #selector(showPreferences(_:)), keyEquivalent: ",")
        settings.target = self

        let permission = menu.addItem(withTitle: "Permiso de grabación de pantalla…",
                                      action: #selector(openScreenRecordingSettings(_:)),
                                      keyEquivalent: "")
        permission.target = self
        permission.tag = 3

        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: "Salir de Tempo", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp

        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    // MARK: - Acciones

    @objc func captureFullScreen(_ sender: Any?) {
        AppCoordinator.shared.captureFullScreen()
    }

    @objc func captureRegion(_ sender: Any?) {
        AppCoordinator.shared.captureRegion()
    }

    @objc func showPreferences(_ sender: Any?) {
        if preferencesController == nil {
            preferencesController = PreferencesWindowController()
        }
        preferencesController?.present()
    }

    @objc func openScreenRecordingSettings(_ sender: Any?) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc func showAbout(_ sender: Any?) {
        showPreferences(sender)
        preferencesController?.select(tab: .about)
    }
}

// MARK: - Estado del menú

extension AppDelegate: NSMenuDelegate {
    /// El menú se actualiza al abrirse: muestra los atajos que estén configurados en ese
    /// momento y el estado real del permiso.
    func menuWillOpen(_ menu: NSMenu) {
        let preferences = Preferences.shared

        if let item = menu.items.first(where: { $0.tag == 1 }) {
            item.title = "\(HotKeyManager.Action.captureFullScreen.title)  ·  \(preferences.fullScreenShortcut.display)"
        }
        if let item = menu.items.first(where: { $0.tag == 2 }) {
            item.title = "\(HotKeyManager.Action.captureRegion.title)…  ·  \(preferences.regionShortcut.display)"
        }
        if let item = menu.items.first(where: { $0.tag == 3 }) {
            item.title = ScreenCaptureService.hasPermission
                ? "Permiso de grabación de pantalla: concedido"
                : "Conceder permiso de grabación de pantalla…"
        }
    }
}
