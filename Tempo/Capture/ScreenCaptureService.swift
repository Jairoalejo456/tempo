import AppKit
import CoreGraphics
import ScreenCaptureKit

/// Captura de pantalla mediante ScreenCaptureKit.
///
/// Se usa `SCScreenshotManager` (macOS 14+) en lugar de la antigua `CGWindowListCreateImage`,
/// que está obsoleta. El filtro excluye siempre la propia aplicación, de modo que ni la
/// miniatura flotante ni la capa de selección aparecen en la imagen resultante.
enum ScreenCaptureService {

    enum CaptureError: LocalizedError {
        case permissionDenied
        case displayNotFound
        case emptyRegion
        case captureFailed(String)

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Tempo necesita permiso de Grabación de pantalla en Ajustes del Sistema › Privacidad y seguridad."
            case .displayNotFound:
                return "No se encontró la pantalla que se quería capturar."
            case .emptyRegion:
                return "La región seleccionada está vacía."
            case let .captureFailed(reason):
                return "No se pudo capturar la pantalla: \(reason)"
            }
        }
    }

    // MARK: - Permisos

    /// `true` si el permiso de Grabación de pantalla ya está concedido.
    static var hasPermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Pide el permiso al sistema. La primera vez muestra el diálogo de macOS; después,
    /// el usuario debe concederlo manualmente en Ajustes del Sistema.
    @discardableResult
    static func requestPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    // MARK: - Captura

    /// Captura completa de la pantalla indicada (por omisión, la que contiene el cursor).
    /// - Parameter includingOwnWindows: sólo para diagnóstico. Normalmente las ventanas de
    ///   Tempo se excluyen para que la miniatura no aparezca dentro de la propia captura.
    static func captureFullScreen(screen: NSScreen? = nil,
                                  includingOwnWindows: Bool = false) async throws -> CaptureImage {
        let target = screen ?? screenUnderCursor()
        guard let target else { throw CaptureError.displayNotFound }
        return try await capture(screen: target, regionInScreen: nil, includingOwnWindows: includingOwnWindows)
    }

    /// Captura una región concreta.
    /// - Parameters:
    ///   - screen: pantalla a la que pertenece la región.
    ///   - regionInScreen: rectángulo en coordenadas globales de AppKit (origen abajo‑izquierda).
    static func captureRegion(screen: NSScreen, regionInScreen rect: CGRect) async throws -> CaptureImage {
        guard rect.width >= 1, rect.height >= 1 else { throw CaptureError.emptyRegion }
        return try await capture(screen: screen, regionInScreen: rect)
    }

    // MARK: - Implementación

    private static func capture(screen: NSScreen,
                                regionInScreen rect: CGRect?,
                                includingOwnWindows: Bool = false) async throws -> CaptureImage {
        guard hasPermission else { throw CaptureError.permissionDenied }
        guard let displayID = screen.displayID else { throw CaptureError.displayNotFound }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            // ScreenCaptureKit devuelve un error genérico cuando falta el permiso TCC.
            throw hasPermission ? CaptureError.captureFailed(error.localizedDescription) : CaptureError.permissionDenied
        }

        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.displayNotFound
        }

        // Excluir la propia aplicación: sus ventanas flotantes nunca deben salir en la captura.
        let ownBundleID = Bundle.main.bundleIdentifier
        let ownApplications = includingOwnWindows
            ? []
            : content.applications.filter { $0.bundleIdentifier == ownBundleID }
        let filter = SCContentFilter(display: display, excludingApplications: ownApplications, exceptingWindows: [])

        let scale = screen.backingScaleFactor
        let configuration = SCStreamConfiguration()
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.scalesToFit = false
        configuration.colorSpaceName = CGColorSpace.sRGB
        if #available(macOS 14.0, *) {
            configuration.captureResolution = .best
        }

        if let rect {
            let source = sourceRect(for: rect, in: screen)
            guard source.width >= 1, source.height >= 1 else { throw CaptureError.emptyRegion }
            configuration.sourceRect = source
            configuration.width = Int((source.width * scale).rounded())
            configuration.height = Int((source.height * scale).rounded())
        } else {
            configuration.width = Int((CGFloat(display.width) * scale).rounded())
            configuration.height = Int((CGFloat(display.height) * scale).rounded())
        }

        do {
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            return CaptureImage(cgImage: image, scale: scale)
        } catch {
            throw CaptureError.captureFailed(error.localizedDescription)
        }
    }

    /// Convierte un rectángulo en coordenadas globales de AppKit (origen abajo‑izquierda)
    /// al sistema que espera ScreenCaptureKit: puntos relativos a la esquina superior
    /// izquierda de la pantalla.
    static func sourceRect(for rect: CGRect, in screen: NSScreen) -> CGRect {
        let frame = screen.frame
        return CGRect(
            x: rect.minX - frame.minX,
            y: frame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    static func screenUnderCursor() -> NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(location) } ?? NSScreen.main
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
