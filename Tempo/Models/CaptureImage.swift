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

    /// Versiones difuminadas de la captura completa, una por nivel de intensidad.
    ///
    /// Cada anotación de blur dibuja únicamente su recorte de estas imágenes. Se guardan en
    /// caché por nivel —no por valor exacto— para no rehacer el filtro mientras se arrastra el
    /// deslizador de intensidad.
    private var cachedBlurs: [Int: CGImage] = [:]
    private let blurLock = NSLock()

    /// Número de niveles distintos de intensidad que se llegan a calcular.
    static let blurLevels = 20

    func blurredImage(intensity: CGFloat = AnnotationStyle.defaultBlurIntensity) -> CGImage? {
        let level = CaptureImage.level(for: intensity)
        blurLock.lock()
        defer { blurLock.unlock() }
        if let cached = cachedBlurs[level] { return cached }
        let produced = CaptureImage.makeBlurred(from: cgImage, level: level)
        cachedBlurs[level] = produced
        return produced
    }

    static func level(for intensity: CGFloat) -> Int {
        let clamped = min(max(intensity, 0), 1)
        return Int((clamped * CGFloat(blurLevels)).rounded())
    }

    /// Radio del difuminado para un nivel dado, en píxeles de la captura.
    ///
    /// Se escala con el tamaño de la imagen para que la censura sea igual de fuerte en una
    /// captura pequeña que en una pantalla completa Retina.
    static func blurRadius(level: Int, for image: CGImage) -> Double {
        let intensity = Double(level) / Double(blurLevels)
        let shortestSide = Double(min(image.width, image.height))
        return max(4, shortestSide * (0.006 + 0.032 * intensity))
    }

    private static func makeBlurred(from image: CGImage, level: Int) -> CGImage? {
        let input = CIImage(cgImage: image)
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
        // `clampedToExtent` evita que los bordes se vuelvan transparentes al difuminar.
        filter.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(blurRadius(level: level, for: image), forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage else { return nil }
        let context = CIContext(options: [.useSoftwareRenderer: false])
        return context.createCGImage(output, from: input.extent)
    }
}
