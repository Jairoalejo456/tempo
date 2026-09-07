import AppKit

// Punto de entrada explícito: la aplicación arranca como utilidad de barra de menús
// (sin icono en el Dock) y sólo pasa a ser una app normal mientras el editor está abierto.
// Modo de diagnóstico: comprueba el flujo real y termina, sin abrir interfaz.
if CommandLine.arguments.contains("--self-check") {
    SelfCheck.run()
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
