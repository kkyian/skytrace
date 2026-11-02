import AppKit
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
let rect = NSRect(x: 38, y: 38, width: 948, height: 948)
let bg = NSBezierPath(roundedRect: rect, xRadius: 218, yRadius: 218)
NSColor(calibratedRed: 0.055, green: 0.083, blue: 0.12, alpha: 1).setFill(); bg.fill()
let accent = NSColor(calibratedRed: 0.36, green: 0.87, blue: 0.73, alpha: 1)
for radius: CGFloat in [160, 290, 395] {
    let circle = NSBezierPath(ovalIn: NSRect(x: 512-radius, y: 512-radius, width: radius*2, height: radius*2))
    accent.withAlphaComponent(0.17).setStroke(); circle.lineWidth = 3; circle.stroke()
}
let cross = NSBezierPath(); cross.move(to: NSPoint(x: 115,y: 512)); cross.line(to: NSPoint(x: 909,y: 512)); cross.move(to: NSPoint(x: 512,y: 115)); cross.line(to: NSPoint(x: 512,y: 909)); cross.lineWidth = 2; accent.withAlphaComponent(0.12).setStroke();cross.stroke()
let plane = NSImage(systemSymbolName: "airplane", accessibilityDescription: nil)!.withSymbolConfiguration(.init(pointSize: 450, weight: .regular))!
let tinted = NSImage(size: plane.size)
tinted.lockFocus();accent.set(); NSRect(origin: .zero, size: plane.size).fill();plane.draw(at: .zero, from: .zero, operation: .destinationIn, fraction: 1);tinted.unlockFocus()
NSGraphicsContext.saveGraphicsState()
let transform = NSAffineTransform();transform.translateX(by: 512,yBy: 512);transform.rotate(byDegrees: 35);transform.concat()
tinted.draw(in: NSRect(x: -230,y: -230,width: 460,height: 460))
NSGraphicsContext.restoreGraphicsState()
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
