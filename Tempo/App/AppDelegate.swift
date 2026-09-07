import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?

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
        registerHotKeys()

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

    // MARK: - Barra de menús

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Tempo")
        item.button?.image?.isTemplate = true

        let menu = NSMenu()

        let full = menu.addItem(withTitle: "Capturar pantalla completa",
                                action: #selector(captureFullScreen(_:)),
                                keyEquivalent: "")
        full.target = self
        full.keyEquivalent = "f"
        full.keyEquivalentModifierMask = [.command, .shift, .option]

        let region = menu.addItem(withTitle: "Capturar región…",
                                  action: #selector(captureRegion(_:)),
                                  keyEquivalent: "")
        region.target = self
        region.keyEquivalent = "s"
        region.keyEquivalentModifierMask = [.command, .shift, .option]

        menu.addItem(.separator())

        let permission = menu.addItem(withTitle: "Permiso de grabación de pantalla…",
                                      action: #selector(openScreenRecordingSettings(_:)),
                                      keyEquivalent: "")
        permission.target = self

        let about = menu.addItem(withTitle: "Acerca de Tempo", action: #selector(showAbout(_:)), keyEquivalent: "")
        about.target = self

        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: "Salir", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp

        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    private func registerHotKeys() {
        let full = HotKeyManager.shared.register(HotKeyManager.fullScreenShortcut) {
            AppCoordinator.shared.captureFullScreen()
        }
        let region = HotKeyManager.shared.register(HotKeyManager.regionShortcut) {
            AppCoordinator.shared.captureRegion()
        }

        if !full || !region {
            NSLog("[Tempo] Alguno de los atajos globales no pudo registrarse; puede estar ocupado por otra aplicación.")
        }
    }

    // MARK: - Acciones

    @objc func captureFullScreen(_ sender: Any?) {
        AppCoordinator.shared.captureFullScreen()
    }

    @objc func captureRegion(_ sender: Any?) {
        AppCoordinator.shared.captureRegion()
    }

    @objc func openScreenRecordingSettings(_ sender: Any?) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc func showAbout(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }
}

// MARK: - Estado del menú

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        guard let item = menu.items.first(where: { $0.action == #selector(openScreenRecordingSettings(_:)) }) else { return }
        item.title = ScreenCaptureService.hasPermission
            ? "Permiso de grabación de pantalla: concedido"
            : "Conceder permiso de grabación de pantalla…"
    }
}
