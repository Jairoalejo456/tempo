import AppKit
import CoreGraphics
import Foundation
import UniformTypeIdentifiers

/// Compone la captura con sus anotaciones y la entrega al sistema:
/// portapapeles, disco (panel de guardar) o archivo temporal para arrastrar.
enum ImageExporter {

    enum ExportError: Error {
        case contextCreationFailed
        case imageCreationFailed
        case encodingFailed
    }

    // MARK: - Composición

    /// Devuelve la imagen final a resolución nativa (incluye el factor Retina de la captura).
    static func compose(capture: CaptureImage, annotations: [Annotation]) throws -> CGImage {
        let pixelWidth = Int(capture.pixelSize.width.rounded())
        let pixelHeight = Int(capture.pixelSize.height.rounded())
        guard pixelWidth > 0, pixelHeight > 0 else { throw ExportError.contextCreationFailed }

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ExportError.contextCreationFailed
        }

        // A partir de aquí se trabaja en puntos lógicos, igual que en pantalla.
        context.scaleBy(x: capture.scale, y: capture.scale)
        AnnotationRenderer.drawBase(capture, in: context)
        AnnotationRenderer.draw(annotations, capture: capture, in: context)

        guard let image = context.makeImage() else { throw ExportError.imageCreationFailed }
        return image
    }

    static func compose(document: EditorDocument) throws -> CGImage {
        try compose(capture: document.capture, annotations: document.annotations)
    }

    // MARK: - Codificación

    static func pngData(from image: CGImage) throws -> Data {
        let representation = NSBitmapImageRep(cgImage: image)
        representation.size = NSSize(width: image.width, height: image.height)
        guard let data = representation.representation(using: .png, properties: [:]) else {
            throw ExportError.encodingFailed
        }
        return data
    }

    // MARK: - Portapapeles

    /// Coloca la imagen en el portapapeles como PNG y TIFF, para que cualquier aplicación
    /// (navegadores, editores, apps de chat) pueda pegarla con ⌘V.
    @discardableResult
    static func copyToPasteboard(image: CGImage) throws -> Bool {
        let data = try pngData(from: image)
        let representation = NSBitmapImageRep(cgImage: image)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let item = NSPasteboardItem()
        item.setData(data, forType: .png)
        if let tiff = representation.tiffRepresentation {
            item.setData(tiff, forType: .tiff)
        }
        return pasteboard.writeObjects([item])
    }

    // MARK: - Guardar

    /// Nombre por defecto, con la fecha de la captura y sin caracteres problemáticos.
    static func suggestedFileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.dateFormat = "yyyy-MM-dd 'a las' HH.mm.ss"
        return "Captura \(formatter.string(from: date)).png"
    }

    /// Escribe la imagen en `url`. Devuelve el error si falla, sin lanzar diálogos.
    static func write(image: CGImage, to url: URL) throws {
        let data = try pngData(from: image)
        try data.write(to: url, options: .atomic)
    }

    // MARK: - Archivo temporal para arrastrar

    /// Carpeta propia dentro del directorio temporal del sistema. Las capturas nunca salen del Mac.
    static var dragFolder: URL {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("Snapper", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// Materializa la imagen final en disco para poder arrastrarla a otra aplicación.
    static func writeTemporaryFile(image: CGImage, date: Date) throws -> URL {
        let name = suggestedFileName(for: date)
        var url = dragFolder.appendingPathComponent(name)
        // Si ya existe (dos capturas en el mismo segundo) se añade un sufijo.
        var attempt = 2
        while FileManager.default.fileExists(atPath: url.path) {
            let stem = (name as NSString).deletingPathExtension
            url = dragFolder.appendingPathComponent("\(stem) (\(attempt)).png")
            attempt += 1
        }
        try write(image: image, to: url)
        return url
    }

    /// Limpia los archivos temporales de sesiones anteriores al arrancar.
    static func cleanTemporaryFiles() {
        let folder = dragFolder
        guard let contents = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return }
        for file in contents {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
