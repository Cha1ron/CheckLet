// 生成 1024x1024 的 App 图标 PNG：swift scripts/make_icon.swift <输出.png>
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let size: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// macOS 图标网格：824x824 圆角矩形，四周留白
let inset: CGFloat = 100
let body = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

NSGraphicsContext.current?.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.shadowBlurRadius = 28
shadow.set()
NSColor.white.setFill()
shape.fill()
NSGraphicsContext.current?.restoreGraphicsState()

NSGradient(colors: [
    NSColor(calibratedRed: 0.33, green: 0.55, blue: 1.0, alpha: 1),
    NSColor(calibratedRed: 0.36, green: 0.82, blue: 0.75, alpha: 1),
])!.draw(in: shape, angle: -55)

// 半透明"悬浮球"
let center = NSPoint(x: size / 2, y: size / 2)
let r: CGFloat = 250
let ball = NSBezierPath(ovalIn: NSRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
NSColor.white.withAlphaComponent(0.22).setFill()
ball.fill()
NSColor.white.withAlphaComponent(0.55).setStroke()
ball.lineWidth = 10
ball.stroke()

// 进度环
let ring = NSBezierPath()
ring.appendArc(withCenter: center, radius: r - 40, startAngle: 90, endAngle: -200, clockwise: true)
ring.lineWidth = 34
ring.lineCapStyle = .round
NSColor.white.setStroke()
ring.stroke()

// 对勾
let check = NSBezierPath()
check.move(to: NSPoint(x: center.x - 95, y: center.y + 5))
check.line(to: NSPoint(x: center.x - 25, y: center.y - 70))
check.line(to: NSPoint(x: center.x + 110, y: center.y + 90))
check.lineWidth = 48
check.lineCapStyle = .round
check.lineJoinStyle = .round
NSColor.white.setStroke()
check.stroke()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("icon → \(out)")
