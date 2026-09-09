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

        // Sólo se borra lo que ya caducó, no lo reciente.
        ImageExporter.cleanTemporaryFiles()
        // Lo que haya caducado en el historial se borra al arrancar.
        DispatchQueue.global(qos: .utility).async {
            CaptureArchive.shared.pruneOldEntries()
        }
        NSApp.mainMenu = MainMenu.build()
        setUpStatusItem()
        setUpHotKeys()

        // Modo demo: abre una captura de ejemplo para probar el editor sin permisos.
        if CommandLine.arguments.contains("--demo") {
            let opensEditor = CommandLine.arguments.contains("--editor")
            let annotated = CommandLine.arguments.contains("--annotated")
            let cropping = CommandLine.arguments.contains("--cropping")
            // `--stack N` abre varias capturas de ejemplo apiladas.
            let stackCount: Int? = CommandLine.arguments.firstIndex(of: "--stack").flatMap { index in
                CommandLine.arguments.count > index + 1 ? Int(CommandLine.arguments[index + 1]) : 3
            }
            DispatchQueue.main.async {
                if let stackCount {
                    AppCoordinator.shared.presentDemoStack(count: stackCount, openingEditor: opensEditor)
                } else {
                    AppCoordinator.shared.presentDemoCapture(openingEditor: opensEditor,
                                                             withSampleAnnotations: annotated,
                                                             cropping: cropping)
                }
            }

            // `--shot <ruta>`: se captura a sí misma pasado un momento, con sus ventanas ya en
            // primer plano. Sirve para revisar la interfaz durante el desarrollo.
            if let index = CommandLine.arguments.firstIndex(of: "--shot"),
               CommandLine.arguments.count > index + 1 {
                let path = CommandLine.arguments[index + 1]
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                    NSApp.activate(ignoringOtherApps: true)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        SelfCheck.captureScreen(to: path, includingOwnWindows: true)
                    }
                }
            }
            return
        }

        applyDockIconPreference()

        // Al arrancar por primera vez se pide el permiso para que el primer atajo ya funcione.
        if !ScreenCaptureService.hasPermission {
            ScreenCaptureService.requestPermission()
        }

        // La primera vez —o si falta el permiso— se muestran los ajustes: al ser una utilidad
        // de barra de menús, arrancar en silencio no daría ninguna señal de que ya funciona.
        if Preferences.shared.consumeFirstLaunchFlag() || !ScreenCaptureService.hasPermission {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.showPreferences(nil)
            }
        }
    }

    /// Abrir Tempo desde Spotlight, Launchpad o el Finder cuando ya está en marcha: se muestran
    /// los ajustes, para que hacer clic en la aplicación tenga una respuesta visible.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showPreferences(nil)
        }
        return true
    }

    /// El usuario puede elegir en los ajustes si Tempo aparece también en el Dock.
    private func applyDockIconPreference() {
        AppCoordinator.shared.updateActivationPolicy()
        Preferences.shared.$showsDockIcon
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { _ in AppCoordinator.shared.updateActivationPolicy() }
            .store(in: &cancellables)
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotKeyManager.shared.unregisterAll()
        // Los archivos de arrastre no se tocan al salir: una imagen soltada hace un momento
        // puede seguir pendiente de leerse en la otra aplicación.
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

        let recent = menu.addItem(withTitle: "Capturas recientes", action: nil, keyEquivalent: "")
        recent.tag = 4
        recent.submenu = NSMenu()

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

    /// Rellena el submenú de capturas recientes con lo que haya en el historial.
    private func rebuildRecentMenu(_ item: NSMenuItem) {
        let submenu = NSMenu()
        let entries = Preferences.shared.keepsHistory ? CaptureArchive.shared.entries() : []

        if entries.isEmpty {
            let empty = submenu.addItem(withTitle: Preferences.shared.keepsHistory
                                        ? "Todavía no hay capturas guardadas"
                                        : "El historial está desactivado",
                                        action: nil, keyEquivalent: "")
            empty.isEnabled = false
        } else {
            for entry in entries.prefix(12) {
                let entryItem = submenu.addItem(withTitle: entry.displayName,
                                                action: #selector(openRecentCapture(_:)),
                                                keyEquivalent: "")
                entryItem.target = self
                entryItem.representedObject = entry.url
                if let image = CaptureArchive.shared.image(at: entry.url) {
                    let thumbnail = NSImage(size: NSSize(width: 44, height: 28))
                    thumbnail.lockFocus()
                    image.draw(in: NSRect(x: 0, y: 0, width: 44, height: 28))
                    thumbnail.unlockFocus()
                    entryItem.image = thumbnail
                }
            }
            submenu.addItem(.separator())
            let clear = submenu.addItem(withTitle: "Vaciar el historial",
                                        action: #selector(clearHistory(_:)), keyEquivalent: "")
            clear.target = self
        }

        item.submenu = submenu
    }

    @objc func openRecentCapture(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL,
              let entry = CaptureArchive.shared.entries().first(where: { $0.url == url }) else { return }
        Task { @MainActor in AppCoordinator.shared.reopen(entry) }
    }

    @objc func clearHistory(_ sender: Any?) {
        CaptureArchive.shared.removeAll()
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
        if let item = menu.items.first(where: { $0.tag == 4 }) {
            rebuildRecentMenu(item)
        }
        if let item = menu.items.first(where: { $0.tag == 3 }) {
            item.title = ScreenCaptureService.hasPermission
                ? "Permiso de grabación de pantalla: concedido"
                : "Conceder permiso de grabación de pantalla…"
        }
    }
}
