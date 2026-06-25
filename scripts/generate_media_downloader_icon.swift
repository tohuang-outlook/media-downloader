import AppKit
import Foundation

let outputPath = CommandLine.arguments.dropFirst().first ?? "MediaDownloaderIcon-1024.png"
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)

func roundedRect(_ rect: NSRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

image.lockFocus()

let bounds = NSRect(origin: .zero, size: size)
NSColor.clear.setFill()
bounds.fill()

let iconRect = NSRect(x: 64, y: 64, width: 896, height: 896)
let background = roundedRect(iconRect, radius: 205)
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.04, green: 0.38, blue: 0.95, alpha: 1),
    NSColor(calibratedRed: 0.04, green: 0.78, blue: 0.72, alpha: 1)
])!
gradient.draw(in: background, angle: -35)

NSColor(calibratedWhite: 1, alpha: 0.18).setStroke()
background.lineWidth = 9
background.stroke()

let shadow = NSShadow()
shadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.24)
shadow.shadowOffset = NSSize(width: 0, height: -18)
shadow.shadowBlurRadius = 28
shadow.set()

NSColor.white.setFill()
let shaft = roundedRect(NSRect(x: 452, y: 405, width: 120, height: 355), radius: 58)
shaft.fill()

let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 313, y: 465))
arrow.line(to: NSPoint(x: 512, y: 250))
arrow.line(to: NSPoint(x: 711, y: 465))
arrow.curve(to: NSPoint(x: 661, y: 530), controlPoint1: NSPoint(x: 693, y: 508), controlPoint2: NSPoint(x: 676, y: 530))
arrow.line(to: NSPoint(x: 572, y: 530))
arrow.line(to: NSPoint(x: 572, y: 405))
arrow.line(to: NSPoint(x: 452, y: 405))
arrow.line(to: NSPoint(x: 452, y: 530))
arrow.line(to: NSPoint(x: 363, y: 530))
arrow.curve(to: NSPoint(x: 313, y: 465), controlPoint1: NSPoint(x: 348, y: 530), controlPoint2: NSPoint(x: 331, y: 508))
arrow.close()
arrow.fill()

let trayOuter = roundedRect(NSRect(x: 270, y: 190, width: 484, height: 120), radius: 56)
trayOuter.fill()

NSColor(calibratedRed: 0.04, green: 0.52, blue: 0.86, alpha: 1).setFill()
let trayInner = roundedRect(NSRect(x: 340, y: 232, width: 344, height: 38), radius: 19)
trayInner.fill()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not render icon PNG")
}

try png.write(to: URL(fileURLWithPath: outputPath))
print(outputPath)
