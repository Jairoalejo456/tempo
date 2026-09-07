import CoreImage
import CoreGraphics
import Foundation

/// Una captura ya realizada: los píxeles nativos más el factor de escala de la pantalla
/// de la que provienen. Todo el editor trabaja en "puntos lógicos" (píxeles / escala),
/// de modo que una pantalla Retina conserva su resolución completa al exportar.
final class CaptureImage {
    let cgImage: CGImage
    let scale: CGFloat
    let createdAt: Date

    init(cgImage: CGImage, scale: CGFloat, createdAt: Date = Date()) {
        self.cgImage = cgImage
        self.scale = max(scale, 1)
        self.createdAt = createdAt
    }

    /// Tamaño en píxeles reales (lo que se guarda o se copia).
    var pixelSize: CGSize {
        CGSize(width: cgImage.width, height: cgImage.height)
    }

    /// Tamaño en puntos: el espacio de coordenadas en el que viven las anotaciones.
    var logicalSize: CGSize {
        CGSize(width: CGFloat(cgImage.width) / scale, height: CGFloat(cgImage.height) / scale)
    }

    var logicalBounds: CGRect {
        CGRect(origin: .zero, size: logicalSize)
    }

    /// Versión difuminada de la captura completa, calculada una sola vez y reutilizada por
    /// todas las anotaciones de blur (cada una dibuja únicamente su recorte).
    private var cachedBlur: CGImage?
    private let blurLock = NSLock()

    func blurredImage() -> CGImage? {
        blurLock.lock()
        defer { blurLock.unlock() }
        if let cachedBlur { return cachedBlur }
        let produced = CaptureImage.makeBlurred(from: cgImage)
        cachedBlur = produced
        return produced
    }

    private static func makeBlurred(from image: CGImage) -> CGImage? {
        let input = CIImage(cgImage: image)
        // El radio se escala con el tamaño para que la censura sea igual de fuerte
        // en una captura pequeña que en una pantalla completa Retina.
        let radius = max(12.0, Double(min(image.width, image.height)) * 0.02)
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
        // `clampedToExtent` evita que los bordes se vuelvan transparentes al difuminar.
        filter.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage else { return nil }
        let context = CIContext(options: [.useSoftwareRenderer: false])
        return context.createCGImage(output, from: input.extent)
    }
}
