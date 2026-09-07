import AppKit
import CoreGraphics
import XCTest
@testable import Snapper

enum TestSupport {

    /// Crea una captura sintética de color uniforme.
    static func makeCapture(logicalWidth: Int = 200,
                            logicalHeight: Int = 120,
                            scale: CGFloat = 2,
                            color: CGColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)) -> CaptureImage {
        let pixelWidth = Int(CGFloat(logicalWidth) * scale)
        let pixelHeight = Int(CGFloat(logicalHeight) * scale)
        let context = CGContext(data: nil,
                                width: pixelWidth,
                                height: pixelHeight,
                                bitsPerComponent: 8,
                                bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(color)
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        return CaptureImage(cgImage: context.makeImage()!, scale: scale)
    }

    /// Captura con dos mitades de color distinto, útil para comprobar el blur.
    static func makeTwoToneCapture(scale: CGFloat = 2) -> CaptureImage {
        let pixelWidth = 200, pixelHeight = 200
        let context = CGContext(data: nil,
                                width: pixelWidth,
                                height: pixelHeight,
                                bitsPerComponent: 8,
                                bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // Franjas verticales muy contrastadas: al difuminar, se mezclan.
        for x in stride(from: 0, to: pixelWidth, by: 8) {
            context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: x, y: 0, width: 4, height: pixelHeight))
            context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: x + 4, y: 0, width: 4, height: pixelHeight))
        }
        return CaptureImage(cgImage: context.makeImage()!, scale: scale)
    }

    /// Lee un píxel (coordenadas en píxeles, origen arriba‑izquierda como en `CGImage`).
    static func pixel(_ image: CGImage, x: Int, y: Int) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        var data = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &data,
                                width: 1,
                                height: 1,
                                bitsPerComponent: 8,
                                bytesPerRow: 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: -CGFloat(x), y: CGFloat(y) - CGFloat(image.height) + 1,
                                       width: CGFloat(image.width), height: CGFloat(image.height)))
        return (CGFloat(data[0]) / 255, CGFloat(data[1]) / 255, CGFloat(data[2]) / 255, CGFloat(data[3]) / 255)
    }

    /// Cuenta cuántos píxeles difieren entre dos imágenes del mismo tamaño.
    static func differingPixelCount(_ a: CGImage, _ b: CGImage) -> Int {
        guard a.width == b.width, a.height == b.height else { return .max }
        let width = a.width, height = a.height
        let bytesPerRow = width * 4
        var bufferA = [UInt8](repeating: 0, count: bytesPerRow * height)
        var bufferB = [UInt8](repeating: 0, count: bytesPerRow * height)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let info = CGImageAlphaInfo.premultipliedLast.rawValue

        CGContext(data: &bufferA, width: width, height: height, bitsPerComponent: 8,
                  bytesPerRow: bytesPerRow, space: space, bitmapInfo: info)?
            .draw(a, in: CGRect(x: 0, y: 0, width: width, height: height))
        CGContext(data: &bufferB, width: width, height: height, bitsPerComponent: 8,
                  bytesPerRow: bytesPerRow, space: space, bitmapInfo: info)?
            .draw(b, in: CGRect(x: 0, y: 0, width: width, height: height))

        var count = 0
        for index in stride(from: 0, to: bufferA.count, by: 4) {
            if abs(Int(bufferA[index]) - Int(bufferB[index])) > 6
                || abs(Int(bufferA[index + 1]) - Int(bufferB[index + 1])) > 6
                || abs(Int(bufferA[index + 2]) - Int(bufferB[index + 2])) > 6 {
                count += 1
            }
        }
        return count
    }
}
