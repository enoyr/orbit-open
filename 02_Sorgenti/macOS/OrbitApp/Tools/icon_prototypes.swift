import AppKit
import CoreGraphics
import CoreText
import Foundation

struct IconVariant {
    let file: String
    let title: String
    let startX: Double
    let endX: Double
    let baselineY: Double
    let phase: Double
    let amplitude: Double
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let variants = [
    IconVariant(file: "A-onda-bordi", title: "A · Onda ai bordi", startX: 0, endX: 1024,
                baselineY: 315, phase: 1.57, amplitude: 1.26),
    IconVariant(file: "B-onda-leggera", title: "B · Onda leggera", startX: 215, endX: 809,
                baselineY: 340, phase: 1.57, amplitude: 0.80),
    IconVariant(file: "C-cresta-destra", title: "C · Cresta a destra", startX: 205, endX: 819,
                baselineY: 325, phase: 0.8, amplitude: 1.05),
]

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> CGColor {
    CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [red, green, blue, 1])!
}

let backgroundColors = [color(1, 1, 1), color(1, 1, 1)]
let letterColors = [color(0.216, 0.345, 1), color(0.22, 0.67, 0.96), color(0, 0.776, 0.69)]
let waveColors = [color(0.216, 0.345, 1), color(0, 0.776, 0.69),
                  color(243 / 255, 229 / 255, 0),
                  color(191 / 255, 54 / 255, 195 / 255), color(1, 0.42, 0.12)]

func gradient(_ context: CGContext, _ colors: [CGColor], from start: CGPoint, to end: CGPoint) {
    let value = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray,
                           locations: nil)!
    context.drawLinearGradient(value, start: start, end: end, options: [])
}

let wordmarkFont = NSFont.systemFont(ofSize: 600, weight: .ultraLight)
let font = CTFontCreateWithName(wordmarkFont.fontName as CFString, 600, nil)
var character: UniChar = 79
var glyph: CGGlyph = 0
guard CTFontGetGlyphsForCharacters(font, &character, &glyph, 1),
      let letter = CTFontCreatePathForGlyph(font, glyph, nil) else {
    fatalError("Impossibile disegnare la O di Orbit")
}
let bounds = letter.boundingBox
let target = CGRect(x: 362, y: 350, width: 300, height: 380)
var transform = CGAffineTransform(translationX: target.minX, y: target.minY)
    .scaledBy(x: target.width / bounds.width, y: target.height / bounds.height)
    .translatedBy(x: -bounds.minX, y: -bounds.minY)
let wordmarkO = letter.copy(using: &transform)!

func wavePath(_ variant: IconVariant, depth: Double) -> CGPath {
    let path = CGMutablePath()
    let weight = 1 - abs(depth) / 20
    let amplitude = (30 + 80 * pow(weight, 2.2)) * variant.amplitude
    for step in 0...240 {
        let unit = Double(step) / 240
        let x = variant.startX + (variant.endX - variant.startX) * unit
        let d = 2 * unit - 1
        let oscillation = sin(d * .pi * 2 + variant.phase + depth * 0.15) * 0.6
            + sin(d * .pi * 6 + variant.phase * 0.8 - depth * 0.25) * 0.4
        let envelope = pow(1 - abs(d), 3)
        let y = variant.baselineY + oscillation * amplitude * envelope * weight
        if step == 0 { path.move(to: CGPoint(x: x, y: y)) }
        else { path.addLine(to: CGPoint(x: x, y: y)) }
    }
    return path
}

func paintWave(_ context: CGContext, variant: IconVariant, depth: Double,
               width: CGFloat, alpha: CGFloat) {
    context.saveGState()
    context.addPath(wavePath(variant, depth: depth))
    context.setLineWidth(width)
    context.replacePathWithStrokedPath()
    context.clip()
    context.setAlpha(alpha)
    gradient(context, waveColors,
             from: CGPoint(x: variant.startX, y: variant.baselineY),
             to: CGPoint(x: variant.endX, y: variant.baselineY))
    context.restoreGState()
}

func render(_ variant: IconVariant) throws -> URL {
    let pixels = 1024
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB,
                                  bytesPerRow: 0, bitsPerPixel: 0)!
    let graphics = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    let context = graphics.cgContext
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)

    let tile = CGPath(roundedRect: CGRect(x: 58, y: 58, width: 908, height: 908),
                      cornerWidth: 215, cornerHeight: 215, transform: nil)
    context.addPath(tile)
    context.clip()
    gradient(context, backgroundColors,
             from: CGPoint(x: 120, y: 900), to: CGPoint(x: 900, y: 120))

    context.saveGState()
    context.addPath(wordmarkO)
    context.clip()
    gradient(context, letterColors,
             from: CGPoint(x: 360, y: 680), to: CGPoint(x: 660, y: 400))
    context.restoreGState()

    for index in 0..<40 {
        let depth = Double(index) - 20
        let weight = 1 - abs(depth) / 20
        paintWave(context, variant: variant, depth: depth, width: 1.15,
                  alpha: CGFloat(0.15 + weight * 0.48))
    }
    paintWave(context, variant: variant, depth: 0, width: 2, alpha: 0.60)

    context.flush()
    NSGraphicsContext.restoreGraphicsState()
    let destination = outputDirectory.appendingPathComponent(variant.file + ".png")
    try bitmap.representation(using: .png, properties: [:])!.write(to: destination)
    return destination
}

for variant in variants {
    let path = try render(variant)
    print(path.path)
}
