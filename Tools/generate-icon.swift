#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

// Genera el icono de Tempo a partir del símbolo del logo: un marco de encuadre de cuatro
// esquinas con un punto de acento. Se dibuja vectorialmente en cada tamaño en lugar de escalar
// un PNG, para que se vea nítido igual a 1024 px que a 16 px en la barra de menús.

let navy = CGColor(srgbRed: 0.086, green: 0.114, blue: 0.278, alpha: 1)   // #161D47
let violet = CGColor(srgbRed: 0.545, green: 0.435, blue: 0.945, alpha: 1) // #8B6FF1
let paper = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)

enum Variant: String {
    case light  // símbolo oscuro sobre fondo claro, como el logo original
    case dark   // símbolo claro sobre fondo azul marino
}

func drawIcon(size: CGFloat, variant: Variant, in context: CGContext) {
    context.translateBy(x: 0, y: size)
    context.scaleBy(x: 1, y: -1) // se piensa en coordenadas con el origen arriba a la izquierda
    context.setShouldAntialias(true)

    // Lienzo del icono: macOS deja margen alrededor del arte.
    let inset = size * 0.09
    let plate = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let corner = plate.width * 0.2237 // radio del «squircle» de macOS

    let platePath = CGPath(roundedRect: plate, cornerWidth: corner, cornerHeight: corner, transform: nil)
    context.addPath(platePath)
    context.setFillColor(variant == .light ? paper : navy)
    context.fillPath()

    if variant == .light {
        // Borde muy tenue para que el icono no se funda con fondos claros.
        context.addPath(platePath)
        context.setStrokeColor(CGColor(srgbRed: 0.086, green: 0.114, blue: 0.278, alpha: 0.12))
        context.setLineWidth(max(1, size * 0.004))
        context.strokePath()
    }

    // Marco de encuadre, centrado dentro del lienzo.
    let frameSide = plate.width * 0.56
    let frame = CGRect(x: plate.midX - frameSide / 2,
                       y: plate.midY - frameSide / 2,
                       width: frameSide,
                       height: frameSide)

    // En tamaños pequeños el trazo se engorda un poco para que siga leyéndose.
    let thicknessRatio: CGFloat = size <= 48 ? 0.150 : (size <= 128 ? 0.125 : 0.112)
    let thickness = frameSide * thicknessRatio
    let arm = frameSide * 0.35
    let radius = thickness * 1.15

    context.setStrokeColor(variant == .light ? navy : paper)
    context.setLineWidth(thickness)
    context.setLineCap(.round)
    context.setLineJoin(.round)

    // Cada esquina es una «L» redondeada.
    let corners: [(CGPoint, CGPoint, CGPoint)] = [
        // (inicio, vértice, fin)
        (CGPoint(x: frame.minX, y: frame.minY + arm), CGPoint(x: frame.minX, y: frame.minY), CGPoint(x: frame.minX + arm, y: frame.minY)),
        (CGPoint(x: frame.maxX - arm, y: frame.minY), CGPoint(x: frame.maxX, y: frame.minY), CGPoint(x: frame.maxX, y: frame.minY + arm)),
        (CGPoint(x: frame.maxX, y: frame.maxY - arm), CGPoint(x: frame.maxX, y: frame.maxY), CGPoint(x: frame.maxX - arm, y: frame.maxY)),
        (CGPoint(x: frame.minX + arm, y: frame.maxY), CGPoint(x: frame.minX, y: frame.maxY), CGPoint(x: frame.minX, y: frame.maxY - arm))
    ]

    for (start, vertex, end) in corners {
        context.beginPath()
        context.move(to: start)
        context.addArc(tangent1End: vertex, tangent2End: end, radius: radius)
        context.addLine(to: end)
        context.strokePath()
    }

    // Punto de acento, dentro del marco junto a la esquina superior derecha.
    let dotRadius = frameSide * 0.115
    let dotCenter = CGPoint(x: frame.minX + frameSide * 0.72,
                            y: frame.minY + frameSide * 0.30)
    context.setFillColor(violet)
    context.fillEllipse(in: CGRect(x: dotCenter.x - dotRadius, y: dotCenter.y - dotRadius,
                                   width: dotRadius * 2, height: dotRadius * 2))
}

func makeImage(size: Int, variant: Variant) -> CGImage? {
    guard let context = CGContext(data: nil,
                                  width: size,
                                  height: size,
                                  bitsPerComponent: 8,
                                  bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    drawIcon(size: CGFloat(size), variant: variant, in: context)
    return context.makeImage()
}

func write(_ image: CGImage, to url: URL) throws {
    let representation = NSBitmapImageRep(cgImage: image)
    guard let data = representation.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "Tempo", code: 1)
    }
    try data.write(to: url)
}

// MARK: - Entrada

let arguments = CommandLine.arguments
let variant = Variant(rawValue: arguments.count > 1 ? arguments[1] : "light") ?? .light
let outputDirectory = URL(fileURLWithPath: arguments.count > 2 ? arguments[2] : ".")
try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let entries: [(points: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)
]

for entry in entries {
    let pixels = entry.points * entry.scale
    guard let image = makeImage(size: pixels, variant: variant) else { continue }
    var name = "icon_\(entry.points)x\(entry.points)"
    if entry.scale == 2 { name += "@2x" }
    let url = outputDirectory.appendingPathComponent("\(name).png")
    try write(image, to: url)
    print("  \(name).png  (\(pixels)px)")
}

// Vista previa a tamaño grande.
if let preview = makeImage(size: 512, variant: variant) {
    try write(preview, to: outputDirectory.appendingPathComponent("preview-\(variant.rawValue).png"))
}

print("Icono generado (\(variant.rawValue)) en \(outputDirectory.path)")
