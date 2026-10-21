// Draws the 1024px app icon: a sunset squircle with a notch hanging from the top edge,
// showing album art and visualizer bars. Usage: swift scripts/make-icon.swift <out.png>
import AppKit

let size = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

// Squircle body on the standard macOS icon grid.
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let squircle = NSBezierPath(roundedRect: body, xRadius: 186, yRadius: 186)

let dropShadow = NSShadow()
dropShadow.shadowColor = color(0x000000, 0.35)
dropShadow.shadowBlurRadius = 30
dropShadow.shadowOffset = NSSize(width: 0, height: -14)
NSGraphicsContext.saveGraphicsState()
dropShadow.set()
color(0x000000).setFill()
squircle.fill()
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.saveGraphicsState()
squircle.addClip()
NSGradient(colors: [color(0xF6A07A), color(0xD9588F), color(0x6B3FA8), color(0x1D1B4A)],
           atLocations: [0, 0.35, 0.72, 1], colorSpace: .sRGB)!
    .draw(in: body, angle: 90)

// Expanded notch: flat top glued to the edge, concave flares, rounded bottom.
let notchWidth: CGFloat = 680, notchHeight: CGFloat = 480, flare: CGFloat = 40, bottom: CGFloat = 120
let left = body.midX - notchWidth / 2, right = body.midX + notchWidth / 2
let top = body.maxY, base = body.maxY - notchHeight
let notch = NSBezierPath()
notch.move(to: NSPoint(x: left - flare, y: top))
notch.curve(to: NSPoint(x: left, y: top - flare), controlPoint1: NSPoint(x: left - flare / 3, y: top),
            controlPoint2: NSPoint(x: left, y: top - flare / 3))
notch.line(to: NSPoint(x: left, y: base + bottom))
notch.curve(to: NSPoint(x: left + bottom, y: base), controlPoint1: NSPoint(x: left, y: base + bottom * 0.45),
            controlPoint2: NSPoint(x: left + bottom * 0.45, y: base))
notch.line(to: NSPoint(x: right - bottom, y: base))
notch.curve(to: NSPoint(x: right, y: base + bottom), controlPoint1: NSPoint(x: right - bottom * 0.45, y: base),
            controlPoint2: NSPoint(x: right, y: base + bottom * 0.45))
notch.line(to: NSPoint(x: right, y: top - flare))
notch.curve(to: NSPoint(x: right + flare, y: top), controlPoint1: NSPoint(x: right, y: top - flare / 3),
            controlPoint2: NSPoint(x: right + flare / 3, y: top))
notch.close()

let glow = NSShadow()
glow.shadowColor = color(0xFF8FB8, 0.7)
glow.shadowBlurRadius = 100
glow.shadowOffset = NSSize(width: 0, height: -30)
NSGraphicsContext.saveGraphicsState()
glow.set()
color(0x000000).setFill()
notch.fill()
NSGraphicsContext.restoreGraphicsState()

// Album art with its own colored glow.
let artSize: CGFloat = 200
let artRect = NSRect(x: left + 70, y: base + 170, width: artSize, height: artSize)
let art = NSBezierPath(roundedRect: artRect, xRadius: 46, yRadius: 46)
let artGlow = NSShadow()
artGlow.shadowColor = color(0x4F7BFF, 0.8)
artGlow.shadowBlurRadius = 50
NSGraphicsContext.saveGraphicsState()
artGlow.set()
color(0x3B6BFF).setFill()
art.fill()
NSGraphicsContext.restoreGraphicsState()
NSGraphicsContext.saveGraphicsState()
art.addClip()
NSGradient(colors: [color(0x5EE7FF), color(0x3B6BFF), color(0x9B4DFF)])!.draw(in: artRect, angle: -45)
NSGraphicsContext.restoreGraphicsState()

// Visualizer bars beside the art.
let heights: [CGFloat] = [0.4, 0.9, 0.6, 1.0, 0.7, 0.35]
let barWidth: CGFloat = 26, gap: CGFloat = 18, maxBar: CGFloat = 170
var x = right - 70 - CGFloat(heights.count) * barWidth - CGFloat(heights.count - 1) * gap
let barGradient = NSGradient(colors: [color(0xFF6FA5), color(0xFFC36B)])!
for h in heights {
    let height = maxBar * h
    let rect = NSRect(x: x, y: artRect.midY - height / 2, width: barWidth, height: height)
    barGradient.draw(in: NSBezierPath(roundedRect: rect, xRadius: barWidth / 2, yRadius: barWidth / 2), angle: 90)
    x += barWidth + gap
}

// Progress bar.
let track = NSRect(x: left + 70, y: base + 92, width: notchWidth - 140, height: 20)
color(0xFFFFFF, 0.22).setFill()
NSBezierPath(roundedRect: track, xRadius: 10, yRadius: 10).fill()
var filled = track
filled.size.width *= 0.62
barGradient.draw(in: NSBezierPath(roundedRect: filled, xRadius: 10, yRadius: 10), angle: 0)
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.restoreGraphicsState()
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("Wrote \(out)")
