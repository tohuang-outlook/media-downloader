import AppKit
import Foundation

let outputPath = CommandLine.arguments.dropFirst().first ?? "SubtitleBurnerIcon-1024.png"
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
    NSColor(calibratedRed: 0.54, green: 0.17, blue: 0.87, alpha: 1),
    NSColor(calibratedRed: 0.98, green: 0.30, blue: 0.44, alpha: 1)
])!
gradient.draw(in: background, angle: -35)

NSColor(calibratedWhite: 1, alpha: 0.18).setStroke()
background.lineWidth = 9
background.stroke()

let shadow = NSShadow()
shadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.24)
shadow.shadowOffset = NSSize(width: 0, height: -16)
shadow.shadowBlurRadius = 26
shadow.set()

NSColor.white.setFill()

let frame = roundedRect(NSRect(x: 230, y: 275, width: 564, height: 420), radius: 54)
frame.fill()

NSColor(calibratedRed: 0.55, green: 0.17, blue: 0.85, alpha: 1).setFill()
let screen = roundedRect(NSRect(x: 282, y: 375, width: 460, height: 260), radius: 34)
screen.fill()

NSColor.white.setFill()
let play = NSBezierPath()
play.move(to: NSPoint(x: 465, y: 455))
play.line(to: NSPoint(x: 465, y: 555))
play.line(to: NSPoint(x: 565, y: 505))
play.close()
play.fill()

let captionBar = roundedRect(NSRect(x: 300, y: 290, width: 424, height: 126), radius: 34)
captionBar.fill()

NSColor(calibratedRed: 0.93, green: 0.22, blue: 0.48, alpha: 1).setFill()
roundedRect(NSRect(x: 348, y: 364, width: 328, height: 22), radius: 11).fill()
roundedRect(NSRect(x: 348, y: 320, width: 148, height: 22), radius: 11).fill()
roundedRect(NSRect(x: 525, y: 320, width: 151, height: 22), radius: 11).fill()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not render icon PNG")
}

try png.write(to: URL(fileURLWithPath: outputPath))
print(outputPath)
