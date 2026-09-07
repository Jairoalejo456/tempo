import AppKit

// Punto de entrada explícito: la aplicación arranca como utilidad de barra de menús
// (sin icono en el Dock) y sólo pasa a ser una app normal mientras el editor está abierto.
// Modos de diagnóstico: comprueban el flujo real y terminan, sin abrir interfaz.
if CommandLine.arguments.contains("--self-check") {
    SelfCheck.run()
}

if let index = CommandLine.arguments.firstIndex(of: "--render-sample") {
    let path = CommandLine.arguments.count > index + 1
        ? CommandLine.arguments[index + 1]
        : "tempo-sample.png"
    SampleRenderer.run(outputPath: path)
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
