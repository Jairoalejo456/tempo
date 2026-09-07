import AppKit
import Foundation

/// Comprobación de extremo a extremo que se ejecuta con `Tempo.app --self-check`.
///
/// Ejercita el camino real (ScreenCaptureKit, composición, portapapeles y escritura en disco)
/// sin necesidad de interacción, para poder verificar la instalación en este Mac. No forma
/// parte del flujo normal de la aplicación.
enum SelfCheck {

    private static var failures = 0
    private static var transcript: [String] = []
    private static var reportURL: URL?

    /// - Parameter reportPath: si se indica, el informe también se escribe ahí.
    ///
    /// Hace falta porque macOS atribuye los permisos de privacidad al proceso que lanza la
    /// aplicación: ejecutar el binario desde una terminal hereda los permisos de la terminal,
    /// no los de Tempo. Lanzándola con `open` y volcando el informe a un archivo se comprueba
    /// el permiso real de la aplicación.
    static func run(reportPath: String? = nil) -> Never {
        reportURL = reportPath.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
        emit("Tempo · comprobación del flujo real")
        emit("")

        guard ScreenCaptureService.hasPermission else {
            emit("✗ Permiso de Grabación de pantalla NO concedido.")
            emit("  Actívalo en Ajustes del Sistema › Privacidad y seguridad › Grabación de pantalla")
            emit("  y vuelve a ejecutar esta comprobación.")
            finish(code: 2)
        }
        report(true, "Permiso de Grabación de pantalla concedido")

        let semaphore = DispatchSemaphore(value: 0)
        Task {
            await runChecks()
            semaphore.signal()
        }
        semaphore.wait()

        emit("")
        if failures == 0 {
            emit("Todas las comprobaciones pasaron.")
            finish(code: 0)
        } else {
            emit("\(failures) comprobación(es) fallaron.")
            finish(code: 1)
        }
    }

    private static func emit(_ line: String) {
        print(line)
        transcript.append(line)
    }

    private static func finish(code: Int32) -> Never {
        if let reportURL {
            try? transcript.joined(separator: "\n").appending("\n")
                .write(to: reportURL, atomically: true, encoding: .utf8)
        }
        exit(code)
    }

    private static func runChecks() async {
        guard let screen = NSScreen.main else {
            report(false, "No hay pantalla principal")
            return
        }
        let scale = screen.backingScaleFactor

        // 1. Captura de pantalla completa.
        var fullCapture: CaptureImage?
        do {
            let capture = try await ScreenCaptureService.captureFullScreen(screen: screen)
            fullCapture = capture
            let expected = CGSize(width: (screen.frame.width * scale).rounded(),
                                  height: (screen.frame.height * scale).rounded())
            let matches = abs(capture.pixelSize.width - expected.width) <= 2
                && abs(capture.pixelSize.height - expected.height) <= 2
            report(matches, "Captura de pantalla completa: \(Int(capture.pixelSize.width))×\(Int(capture.pixelSize.height)) px "
                   + "(esperado \(Int(expected.width))×\(Int(expected.height)), escala \(scale)×)")
        } catch {
            report(false, "Captura de pantalla completa: \(error.localizedDescription)")
        }

        // 2. Captura de una región concreta.
        let region = CGRect(x: screen.frame.minX + 120, y: screen.frame.minY + 140, width: 400, height: 300)
        var regionCapture: CaptureImage?
        do {
            let capture = try await ScreenCaptureService.captureRegion(screen: screen, regionInScreen: region)
            regionCapture = capture
            let expected = CGSize(width: 400 * scale, height: 300 * scale)
            let matches = abs(capture.pixelSize.width - expected.width) <= 2
                && abs(capture.pixelSize.height - expected.height) <= 2
            report(matches, "Captura de región 400×300 pt ⇒ \(Int(capture.pixelSize.width))×\(Int(capture.pixelSize.height)) px "
                   + "(esperado \(Int(expected.width))×\(Int(expected.height)))")
        } catch {
            report(false, "Captura de región: \(error.localizedDescription)")
        }

        guard let capture = regionCapture ?? fullCapture else { return }

        // 3. Anotaciones de todas las herramientas sobre una captura real.
        let document = EditorDocument(capture: capture)
        let size = capture.logicalSize
        document.add(Annotation(shape: .blur(CGRect(x: size.width * 0.05, y: size.height * 0.05,
                                                    width: size.width * 0.3, height: size.height * 0.2)),
                                style: document.currentStyle))
        document.add(Annotation(shape: .rectangle(CGRect(x: size.width * 0.4, y: size.height * 0.1,
                                                         width: size.width * 0.3, height: size.height * 0.2)),
                                style: document.currentStyle))
        document.add(Annotation(shape: .ellipse(CGRect(x: size.width * 0.1, y: size.height * 0.4,
                                                       width: size.width * 0.25, height: size.height * 0.2)),
                                style: document.currentStyle))
        document.add(Annotation(shape: .arrow(from: CGPoint(x: size.width * 0.5, y: size.height * 0.5),
                                              to: CGPoint(x: size.width * 0.8, y: size.height * 0.8)),
                                style: document.currentStyle))
        document.add(Annotation(shape: .pencil(points: (0..<25).map {
            CGPoint(x: size.width * 0.1 + Double($0) * size.width * 0.02,
                    y: size.height * 0.7 + sin(Double($0) / 3) * size.height * 0.05)
        }), style: document.currentStyle))
        document.color = .blue
        document.add(Annotation(shape: .text(origin: CGPoint(x: size.width * 0.1, y: size.height * 0.9),
                                             string: "Prueba"), style: document.currentStyle))
        document.color = .green
        for index in 0..<3 {
            document.add(Annotation(shape: .counter(center: CGPoint(x: size.width * (0.6 + Double(index) * 0.1),
                                                                    y: size.height * 0.35),
                                                    number: document.nextCounterNumber),
                                    style: document.currentStyle))
        }
        report(document.annotations.count == 9, "Se crearon 9 anotaciones (todas las herramientas)")

        let counters = document.annotations.compactMap { annotation -> Int? in
            if case let .counter(_, number) = annotation.shape { return number }
            return nil
        }
        report(counters == [1, 2, 3], "Los contadores se numeraron solos: \(counters)")

        // 4. Deshacer y rehacer.
        let before = document.annotations.count
        document.undo()
        document.undo()
        let afterUndo = document.annotations.count
        document.redo()
        document.redo()
        report(afterUndo == before - 2 && document.annotations.count == before,
               "Deshacer y rehacer devuelven el documento a su estado (\(before) → \(afterUndo) → \(document.annotations.count))")

        // 5. Composición a resolución nativa.
        guard let composed = try? ImageExporter.compose(document: document) else {
            report(false, "Composición de la imagen final")
            return
        }
        report(composed.width == Int(capture.pixelSize.width) && composed.height == Int(capture.pixelSize.height),
               "Imagen final a resolución nativa: \(composed.width)×\(composed.height) px")

        guard let plain = try? ImageExporter.compose(capture: capture, annotations: []) else { return }
        report(!identical(plain, composed), "Las anotaciones aparecen realmente sobre la captura")

        // 6. Portapapeles.
        do {
            try ImageExporter.copyToPasteboard(image: composed)
            let pasted = NSPasteboard.general.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage]
            let image = pasted?.first
            let hasPNG = NSPasteboard.general.data(forType: .png) != nil
            report(image != nil && hasPNG,
                   "Portapapeles listo para ⌘V: \(Int(image?.size.width ?? 0))×\(Int(image?.size.height ?? 0)) pt, PNG disponible")
        } catch {
            report(false, "Copiar al portapapeles: \(error.localizedDescription)")
        }

        // 7. Escritura en disco (lo mismo que hace el panel de guardar tras elegir destino).
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tempo-selfcheck-\(UUID().uuidString).png")
        do {
            try ImageExporter.write(image: composed, to: url)
            let reloaded = NSImage(contentsOf: url)
            let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int ?? 0
            report(reloaded != nil, "Archivo PNG escrito y legible (\(bytes / 1024) KB)")
            emit("   → \(url.path)")
        } catch {
            report(false, "Guardar en disco: \(error.localizedDescription)")
        }

        // 8. Archivo temporal para arrastrar.
        do {
            let dragURL = try ImageExporter.writeTemporaryFile(image: composed, date: Date())
            report(FileManager.default.fileExists(atPath: dragURL.path),
                   "Archivo preparado para arrastrar a otra aplicación")
            emit("   → \(dragURL.path)")
        } catch {
            report(false, "Preparar archivo para arrastrar: \(error.localizedDescription)")
        }
    }

    /// Guarda una captura de la pantalla en `path`. Sirve para revisar la propia interfaz de
    /// Tempo durante el desarrollo: la aplicación es la única con permiso de grabación, así que
    /// una herramienta de línea de órdenes externa no podría hacerlo.
    static func captureScreen(to path: String, includingOwnWindows: Bool = false) -> Never {
        guard ScreenCaptureService.hasPermission else {
            print("Falta el permiso de Grabación de pantalla.")
            exit(2)
        }
        let semaphore = DispatchSemaphore(value: 0)
        var exitCode: Int32 = 1
        Task {
            defer { semaphore.signal() }
            do {
                let capture = try await ScreenCaptureService.captureFullScreen(includingOwnWindows: includingOwnWindows)
                let image = try ImageExporter.compose(capture: capture, annotations: [])
                let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
                try ImageExporter.write(image: image, to: url)
                print("Captura guardada en \(url.path) (\(image.width)×\(image.height) px)")
                exitCode = 0
            } catch {
                print("No se pudo capturar: \(error.localizedDescription)")
            }
        }
        semaphore.wait()
        exit(exitCode)
    }

    private static func identical(_ a: CGImage, _ b: CGImage) -> Bool {
        guard let dataA = a.dataProvider?.data, let dataB = b.dataProvider?.data else { return false }
        return (dataA as Data) == (dataB as Data)
    }

    private static func report(_ success: Bool, _ message: String) {
        if !success { failures += 1 }
        emit("\(success ? "✓" : "✗") \(message)")
    }
}
