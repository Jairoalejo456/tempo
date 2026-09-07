import AppKit

// Punto de entrada explícito: la aplicación arranca como utilidad de barra de menús
// (sin icono en el Dock) y sólo pasa a ser una app normal mientras el editor está abierto.
// Modos de diagnóstico: comprueban el flujo real y terminan, sin abrir interfaz.
if let index = CommandLine.arguments.firstIndex(of: "--self-check") {
    // Acepta una ruta opcional donde volcar el informe, para poder lanzarla con `open`.
    let next = CommandLine.arguments.count > index + 1 ? CommandLine.arguments[index + 1] : nil
    SelfCheck.run(reportPath: next?.hasPrefix("-") == false ? next : nil)
}

if let index = CommandLine.arguments.firstIndex(of: "--screenshot"),
   CommandLine.arguments.count > index + 1 {
    SelfCheck.captureScreen(to: CommandLine.arguments[index + 1],
                            includingOwnWindows: CommandLine.arguments.contains("--include-self"))
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
