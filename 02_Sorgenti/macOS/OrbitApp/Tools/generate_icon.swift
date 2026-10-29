import AppKit
import CoreGraphics
import CoreText
import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let size = 1024
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
    isPlanar: false, colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0
), let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Impossibile creare l'icona")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphics
let context = graphics.cgContext
context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [red, green, blue, alpha])!
}

func gradient(_ colors: [CGColor], from start: CGPoint, to end: CGPoint) {
    let value = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray,
                           locations: nil)!
    context.drawLinearGradient(value, start: start, end: end, options: [])
}

// White macOS tile used by the approved Orbit icon.
let tile = CGPath(roundedRect: CGRect(x: 58, y: 58, width: 908, height: 908),
                  cornerWidth: 215, cornerHeight: 215, transform: nil)
context.addPath(tile)
context.clip()
gradient([color(1, 1, 1), color(1, 1, 1)],
         from: CGPoint(x: 120, y: 900), to: CGPoint(x: 900, y: 120))

// Use the same system Ultra Light O as the Orbit wordmark, scaled for the icon.
let wordmarkFont = NSFont.systemFont(ofSize: 600, weight: .ultraLight)
let font = CTFontCreateWithName(wordmarkFont.fontName as CFString, 600, nil)
var character: UniChar = 79
var glyph: CGGlyph = 0
guard CTFontGetGlyphsForCharacters(font, &character, &glyph, 1),
      let letter = CTFontCreatePathForGlyph(font, glyph, nil) else {
    fatalError("Impossibile disegnare la O")
}
let bounds = letter.boundingBox
let target = CGRect(x: 362, y: 350, width: 300, height: 380)
var transform = CGAffineTransform(translationX: target.minX, y: target.minY)
    .scaledBy(x: target.width / bounds.width, y: target.height / bounds.height)
    .translatedBy(x: -bounds.minX, y: -bounds.minY)
guard let wordmarkO = letter.copy(using: &transform) else {
    fatalError("Impossibile posizionare la O")
}
context.saveGState()
context.addPath(wordmarkO)
context.clip()
gradient([color(0.216, 0.345, 1), color(0.22, 0.67, 0.96), color(0, 0.776, 0.69)],
         from: CGPoint(x: 360, y: 680), to: CGPoint(x: 660, y: 400))
context.restoreGState()

// Match the Home wave's colors, oscillation and 40-line construction.
let waveColors = [color(0.216, 0.345, 1), color(0, 0.776, 0.69),
                  color(243 / 255, 229 / 255, 0),
                  color(191 / 255, 54 / 255, 195 / 255), color(1, 0.42, 0.12)]

func wavePath(depth: Double) -> CGPath {
    let path = CGMutablePath()
    let weight = 1 - abs(depth) / 20
    let amplitude = (30 + 80 * pow(weight, 2.2)) * 1.26
    for step in 0...240 {
        let unit = Double(step) / 240
        let x = 59 + 906 * unit
        let d = 2 * unit - 1
        let oscillation = sin(d * .pi * 2 + 1.57 + depth * 0.15) * 0.6
            + sin(d * .pi * 6 + 1.57 * 0.8 - depth * 0.25) * 0.4
        let envelope = pow(1 - abs(d), 3)
        let y = 315 + oscillation * amplitude * envelope * weight
        if step == 0 { path.move(to: CGPoint(x: x, y: y)) }
        else { path.addLine(to: CGPoint(x: x, y: y)) }
    }
    return path
}

func paintWave(_ path: CGPath, width: CGFloat, alpha: CGFloat) {
    context.saveGState()
    context.addPath(path)
    context.setLineWidth(width)
    context.replacePathWithStrokedPath()
    context.clip()
    context.setAlpha(alpha)
    gradient(waveColors, from: CGPoint(x: 59, y: 315), to: CGPoint(x: 965, y: 315))
    context.restoreGState()
}

for index in 0..<40 {
    let depth = Double(index) - 20
    let weight = 1 - abs(depth) / 20
    paintWave(wavePath(depth: depth), width: 1.15,
              alpha: CGFloat(0.15 + weight * 0.48))
}
paintWave(wavePath(depth: 0), width: 2, alpha: 0.60)

context.flush()
NSGraphicsContext.restoreGraphicsState()
guard let data = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Impossibile esportare l'icona")
}
try data.write(to: output)
