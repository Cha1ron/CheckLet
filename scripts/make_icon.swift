// 生成 1024x1024 的 App 图标 PNG：swift scripts/make_icon.swift <输出.png>
// 造型：马卡龙渐变背景上，一颗软萌的"麻薯小球"顶着一枚对勾贴纸，周围点缀星星。
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let S: CGFloat = 1024

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
func oval(_ cx: CGFloat, _ cy: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSBezierPath {
    NSBezierPath(ovalIn: NSRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h))
}
func withShadow(_ color: NSColor, blur: CGFloat, dy: CGFloat, _ draw: () -> Void) {
    NSGraphicsContext.current?.saveGraphicsState()
    let s = NSShadow()
    s.shadowColor = color
    s.shadowBlurRadius = blur
    s.shadowOffset = NSSize(width: 0, height: dy)
    s.set()
    draw()
    NSGraphicsContext.current?.restoreGraphicsState()
}
/// 四角星 ✦
func sparkle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ color: NSColor) {
    let p = NSBezierPath()
    let k = r * 0.22
    p.move(to: NSPoint(x: cx, y: cy + r))
    p.curve(to: NSPoint(x: cx + r, y: cy), controlPoint1: NSPoint(x: cx + k, y: cy + k), controlPoint2: NSPoint(x: cx + k, y: cy + k))
    p.curve(to: NSPoint(x: cx, y: cy - r), controlPoint1: NSPoint(x: cx + k, y: cy - k), controlPoint2: NSPoint(x: cx + k, y: cy - k))
    p.curve(to: NSPoint(x: cx - r, y: cy), controlPoint1: NSPoint(x: cx - k, y: cy - k), controlPoint2: NSPoint(x: cx - k, y: cy - k))
    p.curve(to: NSPoint(x: cx, y: cy + r), controlPoint1: NSPoint(x: cx - k, y: cy + k), controlPoint2: NSPoint(x: cx - k, y: cy + k))
    p.close()
    color.setFill()
    p.fill()
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// ── 背景：macOS 图标网格 824×824 圆角方块，马卡龙渐变 ──
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let bg = NSBezierPath(roundedRect: body, xRadius: 186, yRadius: 186)
withShadow(rgb(0x6B4E9B, 0.28), blur: 30, dy: -14) {
    rgb(0xFFFFFF).setFill()
    bg.fill()
}
NSGradient(colors: [rgb(0xFFC2DA), rgb(0xE6C6FF), rgb(0xA9D8FF)],
           atLocations: [0, 0.5, 1], colorSpace: .sRGB)!.draw(in: bg, angle: -50)

NSGraphicsContext.current?.saveGraphicsState()
bg.addClip()
// 背景里的柔光泡泡
rgb(0xFFFFFF, 0.28).setFill()
oval(230, 820, 260, 260).fill()
rgb(0xFFFFFF, 0.18).setFill()
oval(860, 180, 320, 320).fill()
// 星星和小圆点
sparkle(240, 700, 46, rgb(0xFFFFFF, 0.95))
sparkle(800, 820, 34, rgb(0xFFFFFF, 0.9))
sparkle(805, 300, 26, rgb(0xFFFFFF, 0.85))
sparkle(220, 300, 20, rgb(0xFFFFFF, 0.8))
rgb(0xFFFFFF, 0.8).setFill()
oval(300, 800, 16, 16).fill()
oval(760, 230, 14, 14).fill()
oval(175, 470, 12, 12).fill()
NSGraphicsContext.current?.restoreGraphicsState()

// ── 地面上的影子：表示小球是"浮"起来的 ──
NSGradient(colors: [rgb(0x7B5EA7, 0.30), rgb(0x7B5EA7, 0)])!
    .draw(in: oval(512, 190, 360, 56), relativeCenterPosition: .zero)

// ── 麻薯小球 ──
let cx: CGFloat = 512, cy: CGFloat = 468, r: CGFloat = 262
let ball = oval(cx, cy, r * 2, r * 2 * 0.96)
withShadow(rgb(0x8A5FB8, 0.35), blur: 40, dy: -18) {
    rgb(0xFFF6FA).setFill()
    ball.fill()
}
NSGradient(colors: [rgb(0xFFFFFF), rgb(0xFFEFF6), rgb(0xFFCFE3)],
           atLocations: [0, 0.6, 1], colorSpace: .sRGB)!
    .draw(in: ball, relativeCenterPosition: NSPoint(x: -0.35, y: 0.4))

// 高光
NSGraphicsContext.current?.saveGraphicsState()
let xf = NSAffineTransform()
xf.translateX(by: 395, yBy: 625)
xf.rotate(byDegrees: 32)
xf.concat()
rgb(0xFFFFFF, 0.95).setFill()
oval(0, 0, 96, 46).fill()
NSGraphicsContext.current?.restoreGraphicsState()
rgb(0xFFFFFF, 0.9).setFill()
oval(330, 570, 22, 22).fill()

// 腮红
rgb(0xFF8FB3, 0.55).setFill()
oval(394, 410, 80, 42).fill()
oval(630, 410, 80, 42).fill()

// 眼睛
let ink = rgb(0x3D2C5A)
ink.setFill()
oval(452, 476, 60, 76).fill()
oval(572, 476, 60, 76).fill()
rgb(0xFFFFFF).setFill()
oval(464, 496, 22, 22).fill()
oval(584, 496, 22, 22).fill()
oval(443, 458, 10, 10).fill()
oval(563, 458, 10, 10).fill()

// 嘴巴 ω
let mouth = NSBezierPath()
mouth.move(to: NSPoint(x: 478, y: 430))
mouth.curve(to: NSPoint(x: 512, y: 426), controlPoint1: NSPoint(x: 484, y: 404), controlPoint2: NSPoint(x: 508, y: 402))
mouth.curve(to: NSPoint(x: 546, y: 430), controlPoint1: NSPoint(x: 516, y: 402), controlPoint2: NSPoint(x: 540, y: 404))
mouth.lineWidth = 11
mouth.lineCapStyle = .round
mouth.lineJoinStyle = .round
ink.setStroke()
mouth.stroke()

// ── 对勾贴纸 ──
let bx: CGFloat = 712, by: CGFloat = 664, br: CGFloat = 104
let badge = oval(bx, by, br * 2, br * 2)
withShadow(rgb(0x2E8F72, 0.35), blur: 22, dy: -8) {
    rgb(0xFFFFFF).setFill()
    badge.fill()
}
NSGradient(colors: [rgb(0x8DF0C4), rgb(0x3CCB95)])!
    .draw(in: oval(bx, by, (br - 13) * 2, (br - 13) * 2), angle: -70)
let check = NSBezierPath()
check.move(to: NSPoint(x: bx - 44, y: by + 2))
check.line(to: NSPoint(x: bx - 12, y: by - 30))
check.line(to: NSPoint(x: bx + 46, y: by + 34))
check.lineWidth = 26
check.lineCapStyle = .round
check.lineJoinStyle = .round
rgb(0xFFFFFF).setStroke()
check.stroke()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("icon → \(out)")
