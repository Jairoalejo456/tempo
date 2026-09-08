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

    // MARK: - Reducir

    /// Reduce la imagen para que su lado mayor no pase de `maximumSide`.
    ///
    /// Una captura Retina ronda los 2800 px de ancho, pero los chats de inteligencia artificial
    /// reescalan internamente a bastante menos, así que enviar el original es mandar datos que
    /// nadie va a mirar. Guardar en disco sí conserva siempre el tamaño completo.
    static func resized(_ image: CGImage, maximumSide: CGFloat) -> CGImage {
        let longest = CGFloat(max(image.width, image.height))
        guard longest > maximumSide, maximumSide > 0 else { return image }

        let factor = maximumSide / longest
        let width = Int((CGFloat(image.width) * factor).rounded())
        let height = Int((CGFloat(image.height) * factor).rounded())
        guard width > 0, height > 0 else { return image }

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return image
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
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
    static func copyToPasteboard(image: CGImage, maximumSide: CGFloat? = nil) throws -> Bool {
        let image = maximumSide.map { resized(image, maximumSide: $0) } ?? image
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

    /// Devuelve una ruta libre dentro de `folder`, añadiendo un sufijo si el nombre ya existe.
    /// Se usa al guardar sin preguntar, para no sobrescribir nunca una captura anterior.
    static func availableURL(for fileName: String, in folder: URL) -> URL {
        var url = folder.appendingPathComponent(fileName)
        let stem = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var attempt = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(stem) (\(attempt)).\(ext)")
            attempt += 1
        }
        return url
    }

    /// Escribe la imagen en `url`. Devuelve el error si falla, sin lanzar diálogos.
    static func write(image: CGImage, to url: URL) throws {
        let data = try pngData(from: image)
        try data.write(to: url, options: .atomic)
    }

    // MARK: - Archivo temporal para arrastrar

    /// Carpeta propia dentro del directorio temporal del sistema. Las capturas nunca salen del Mac.
    static var dragFolder: URL {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("Tempo", isDirectory: true)
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

    /// Cuánto tiempo se conserva un archivo de arrastre antes de considerarlo caducado.
    static let dragFileLifetime: TimeInterval = 24 * 60 * 60

    /// Borra los archivos de arrastre que ya han caducado.
    ///
    /// Es importante **no** borrarlos en cuanto se cierra la captura: al soltar una imagen,
    /// muchas aplicaciones no se quedan con una copia sino con la ruta del archivo, y sólo lo
    /// leen más tarde —por ejemplo al enviar el mensaje—. Si el archivo hubiera desaparecido
    /// para entonces, la imagen aparecería como no disponible en el chat.
    static func cleanTemporaryFiles(olderThan lifetime: TimeInterval = dragFileLifetime) {
        let folder = dragFolder
        let manager = FileManager.default
        guard let contents = try? manager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.contentModificationDateKey]) else { return }

        let deadline = Date().addingTimeInterval(-lifetime)
        for file in contents {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            if modified < deadline {
                try? manager.removeItem(at: file)
            }
        }
    }
}
