import AppKit
import SwiftUI

/// Ventana de ajustes de la aplicación.
final class PreferencesWindowController: NSWindowController, NSWindowDelegate {

    /// Mientras los ajustes están abiertos, Tempo se comporta como una aplicación normal
    /// (aparece en el Dock) aunque no haya ningún editor.
    private(set) static var isShowing = false

    private var selection: PreferencesTab = .general {
        didSet { rebuild() }
    }

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 380),
                              styleMask: [.titled, .closable],
                              backing: .buffered,
                              defer: false)
        window.title = "Ajustes de Tempo"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        rebuild()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) no está soportado")
    }

    private func rebuild() {
        let binding = Binding<PreferencesTab>(
            get: { [weak self] in self?.selection ?? .general },
            set: { [weak self] newValue in
                guard self?.selection != newValue else { return }
                self?.selection = newValue
            }
        )
        let view = PreferencesView(preferences: Preferences.shared, selection: binding)
        if let hosting = window?.contentView as? NSHostingView<PreferencesView> {
            hosting.rootView = view
        } else {
            window?.contentView = NSHostingView(rootView: view)
        }
        window?.setContentSize(window?.contentView?.fittingSize ?? NSSize(width: 500, height: 380))
    }

    func present() {
        // Los ajustes son una ventana normal: la aplicación pasa al primer plano mientras tanto.
        PreferencesWindowController.isShowing = true
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        PreferencesWindowController.isShowing = false
        // Al cerrar, la aplicación vuelve a la barra de menús salvo que el usuario haya pedido
        // mantener el icono en el Dock.
        DispatchQueue.main.async {
            AppCoordinator.shared.updateActivationPolicy()
        }
    }

    func select(tab: PreferencesTab) {
        selection = tab
    }
}
