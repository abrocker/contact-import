// Zeichnet das App-Symbol (Liquid-Glass-Stil) als 1024×1024 PNG.
// Aufruf: swift tools/make_icon.swift <ausgabe.png>
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"

let cs = CGColorSpace(name: CGColorSpace.displayP3)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [r / 255, g / 255, b / 255, a])!
}

func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: cs, colors: colors as CFArray, locations: locations)!
}

/// Superellipse ("Squircle") wie bei Apple-Symbolen.
func squircle(_ rect: CGRect, n: CGFloat = 5.0) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    let cx = rect.midX, cy = rect.midY
    let steps = 720
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = cx + a * (c >= 0 ? 1 : -1) * pow(abs(c), 2 / n)
        let y = cy + b * (s >= 0 ? 1 : -1) * pow(abs(s), 2 / n)
        i == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    return path
}

func roundedRect(_ rect: CGRect, _ r: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
}

/// Glasfläche: halbtransparente Füllung, Lichtkante oben, weicher Schatten.
func drawGlass(_ path: CGPath, tint: CGColor, fillAlpha: CGFloat, shadowBlur: CGFloat = 40) {
    let box = path.boundingBox

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: shadowBlur, color: rgb(8, 20, 70, 0.35))
    ctx.addPath(path)
    ctx.setFillColor(tint.copy(alpha: fillAlpha)!)
    ctx.fillPath()
    ctx.restoreGState()

    // Innerer Verlauf: oben heller, unten klarer
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    ctx.drawLinearGradient(gradient([rgb(255, 255, 255, 0.38), rgb(255, 255, 255, 0.06)], [0, 1]),
                           start: CGPoint(x: box.midX, y: box.maxY), end: CGPoint(x: box.midX, y: box.minY), options: [])
    ctx.restoreGState()

    // Lichtkante (Rim)
    ctx.saveGState()
    ctx.addPath(path)
    ctx.setLineWidth(6)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    ctx.drawLinearGradient(gradient([rgb(255, 255, 255, 0.95), rgb(255, 255, 255, 0.15), rgb(255, 255, 255, 0.55)], [0, 0.55, 1]),
                           start: CGPoint(x: box.minX, y: box.maxY), end: CGPoint(x: box.maxX, y: box.minY),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

// MARK: Hintergrund-Squircle (macOS-Raster: 824 pt in 1024 pt)

let iconRect = CGRect(x: 100, y: 100, width: 824, height: 824)
let iconPath = squircle(iconRect)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0, 0, 0, 0.30))
ctx.addPath(iconPath)
ctx.setFillColor(rgb(30, 80, 220))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(iconPath); ctx.clip()
ctx.drawLinearGradient(gradient([rgb(92, 196, 255), rgb(45, 118, 255), rgb(70, 52, 214)], [0, 0.55, 1]),
                       start: CGPoint(x: 300, y: 924), end: CGPoint(x: 724, y: 100),
                       options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
// weiches Licht oben links
ctx.drawRadialGradient(gradient([rgb(255, 255, 255, 0.35), rgb(255, 255, 255, 0)], [0, 1]),
                       startCenter: CGPoint(x: 330, y: 820), startRadius: 0,
                       endCenter: CGPoint(x: 330, y: 820), endRadius: 520, options: [])
ctx.restoreGState()

// MARK: Hintere Karte (Zwischenablage)

let backCard = CGRect(x: 268, y: 330, width: 470, height: 340)
ctx.saveGState()
ctx.translateBy(x: backCard.midX, y: backCard.midY)
ctx.rotate(by: 0.16)
ctx.translateBy(x: -backCard.midX, y: -backCard.midY)
drawGlass(roundedRect(backCard.offsetBy(dx: 40, dy: 70), 64), tint: rgb(255, 255, 255), fillAlpha: 0.16, shadowBlur: 30)
ctx.restoreGState()

// MARK: Vordere Kontaktkarte

let card = CGRect(x: 222, y: 300, width: 540, height: 380)
drawGlass(roundedRect(card, 72), tint: rgb(255, 255, 255), fillAlpha: 0.22)

// Person
let white = rgb(255, 255, 255, 0.96)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 10, color: rgb(10, 30, 120, 0.25))
ctx.setFillColor(white)
ctx.fillEllipse(in: CGRect(x: 300, y: 500, width: 118, height: 118))
let body = CGMutablePath()
body.addRoundedRect(in: CGRect(x: 268, y: 372, width: 182, height: 112), cornerWidth: 56, cornerHeight: 56)
ctx.addPath(body)
ctx.fillPath()

// Textzeilen
ctx.setFillColor(rgb(255, 255, 255, 0.92))
ctx.addPath(roundedRect(CGRect(x: 494, y: 552, width: 200, height: 34), 17)); ctx.fillPath()
ctx.setFillColor(rgb(255, 255, 255, 0.6))
ctx.addPath(roundedRect(CGRect(x: 494, y: 488, width: 160, height: 26), 13)); ctx.fillPath()
ctx.addPath(roundedRect(CGRect(x: 494, y: 432, width: 186, height: 26), 13)); ctx.fillPath()
ctx.restoreGState()

// MARK: Plus-Badge

let badge = CGRect(x: 612, y: 196, width: 210, height: 210)
let badgePath = CGPath(ellipseIn: badge, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: rgb(0, 40, 20, 0.35))
ctx.addPath(badgePath); ctx.setFillColor(rgb(48, 209, 88)); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(badgePath); ctx.clip()
ctx.drawLinearGradient(gradient([rgb(120, 240, 150), rgb(40, 190, 85), rgb(20, 150, 70)], [0, 0.6, 1]),
                       start: CGPoint(x: badge.midX, y: badge.maxY), end: CGPoint(x: badge.midX, y: badge.minY), options: [])
ctx.restoreGState()
drawGlass(badgePath, tint: rgb(255, 255, 255), fillAlpha: 0.0, shadowBlur: 0)

ctx.setFillColor(rgb(255, 255, 255))
let bar: CGFloat = 30, len: CGFloat = 104
ctx.addPath(roundedRect(CGRect(x: badge.midX - len / 2, y: badge.midY - bar / 2, width: len, height: bar), bar / 2)); ctx.fillPath()
ctx.addPath(roundedRect(CGRect(x: badge.midX - bar / 2, y: badge.midY - len / 2, width: bar, height: len), bar / 2)); ctx.fillPath()

// MARK: Lichtkante des Symbols

ctx.saveGState()
ctx.addPath(iconPath)
ctx.setLineWidth(5)
ctx.replacePathWithStrokedPath()
ctx.clip()
ctx.drawLinearGradient(gradient([rgb(255, 255, 255, 0.75), rgb(255, 255, 255, 0.05), rgb(255, 255, 255, 0.3)], [0, 0.5, 1]),
                       start: CGPoint(x: 100, y: 924), end: CGPoint(x: 924, y: 100),
                       options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
ctx.restoreGState()

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("Geschrieben: \(out)")
