import AppKit

/// Menú principal construido en código (la aplicación no usa storyboards).
///
/// Los elementos apuntan a `nil` como destino para que macOS los enrute por la cadena de
/// respondedores: así se activan solos cuando hay un editor abierto y se desactivan cuando no,
/// que es justo lo que debe ocurrir al pulsar ⌘C o ⌘S sin ninguna captura activa.
enum MainMenu {

    static func build() -> NSMenu {
        let main = NSMenu()

        main.addItem(applicationMenuItem())
        main.addItem(captureMenuItem())
        main.addItem(editMenuItem())
        main.addItem(viewMenuItem())
        main.addItem(toolsMenuItem())

        return main
    }

    // MARK: - Tempo

    private static func applicationMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "Tempo")

        menu.addItem(withTitle: "Acerca de Tempo", action: #selector(AppDelegate.showAbout(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        let settings = menu.addItem(withTitle: "Ajustes…", action: #selector(AppDelegate.showPreferences(_:)), keyEquivalent: ",")
        settings.keyEquivalentModifierMask = [.command]
        menu.addItem(.separator())
        menu.addItem(withTitle: "Ocultar Tempo", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Salir de Tempo", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        item.submenu = menu
        return item
    }

    // MARK: - Captura

    private static func captureMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "Captura")

        let full = menu.addItem(withTitle: "Capturar pantalla completa",
                                action: #selector(AppDelegate.captureFullScreen(_:)),
                                keyEquivalent: "f")
        full.keyEquivalentModifierMask = [.command, .shift, .option]

        let region = menu.addItem(withTitle: "Capturar región…",
                                  action: #selector(AppDelegate.captureRegion(_:)),
                                  keyEquivalent: "s")
        region.keyEquivalentModifierMask = [.command, .shift, .option]

        menu.addItem(.separator())

        let save = menu.addItem(withTitle: "Guardar como PNG…",
                                action: #selector(EditorWindowController.saveImage(_:)),
                                keyEquivalent: "s")
        save.keyEquivalentModifierMask = [.command]

        menu.addItem(.separator())

        let close = menu.addItem(withTitle: "Volver a la miniatura",
                                 action: #selector(EditorWindowController.returnToThumbnail(_:)),
                                 keyEquivalent: "w")
        close.keyEquivalentModifierMask = [.command]

        let discard = menu.addItem(withTitle: "Descartar captura",
                                   action: #selector(EditorWindowController.discardCapture(_:)),
                                   keyEquivalent: "\u{8}")
        discard.keyEquivalentModifierMask = [.command, .shift]

        item.submenu = menu
        return item
    }

    // MARK: - Edición

    private static func editMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "Edición")

        menu.addItem(withTitle: "Deshacer", action: #selector(EditorWindowController.undoEdit(_:)), keyEquivalent: "z")
        let redo = menu.addItem(withTitle: "Rehacer", action: #selector(EditorWindowController.redoEdit(_:)), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]

        menu.addItem(.separator())

        // Primero el "Copiar" estándar: mientras se escribe una anotación de texto es el que
        // responde. Cuando no hay edición de texto, nadie lo atiende y macOS pasa al siguiente.
        menu.addItem(withTitle: "Copiar", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Copiar imagen con anotaciones",
                     action: #selector(EditorWindowController.copyImage(_:)),
                     keyEquivalent: "c")

        menu.addItem(.separator())
        menu.addItem(withTitle: "Cortar", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "Pegar", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: "Seleccionar todo", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        item.submenu = menu
        return item
    }

    // MARK: - Visualización

    private static func viewMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "Visualización")

        menu.addItem(withTitle: "Acercar", action: #selector(EditorWindowController.zoomIn(_:)), keyEquivalent: "+")
        // Duplicado con "=", que es donde está el "+" sin Mayúsculas en muchos teclados. El
        // ítem se oculta del menú, pero su atajo sigue funcionando.
        let zoomInAlternate = menu.addItem(withTitle: "Acercar",
                                           action: #selector(EditorWindowController.zoomIn(_:)),
                                           keyEquivalent: "=")
        zoomInAlternate.isHidden = true
        zoomInAlternate.isAlternate = false

        menu.addItem(withTitle: "Alejar", action: #selector(EditorWindowController.zoomOut(_:)), keyEquivalent: "-")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Ajustar a la ventana", action: #selector(EditorWindowController.zoomToFit(_:)), keyEquivalent: "0")
        menu.addItem(withTitle: "Tamaño real", action: #selector(EditorWindowController.zoomToActualSize(_:)), keyEquivalent: "1")

        item.submenu = menu
        return item
    }

    // MARK: - Herramientas (informativo: los atajos los gestiona el editor)

    private static func toolsMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "Herramientas")

        for tool in EditorTool.allCases {
            let entry = NSMenuItem(title: "\(tool.title)  ·  \(tool.shortcutKey.uppercased())", action: nil, keyEquivalent: "")
            entry.isEnabled = false
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        let hint = NSMenuItem(title: "Con el editor abierto, pulsa la tecla indicada", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)

        item.submenu = menu
        return item
    }
}
