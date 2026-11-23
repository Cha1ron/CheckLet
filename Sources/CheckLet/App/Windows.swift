import AppKit

/// 不抢焦点、浮在所有窗口上方、跟随所有桌面空间的面板
final class FloatingPanel: NSPanel {
    private let allowKey: Bool
    var onEscape: (() -> Void)?

    init(contentRect: NSRect, allowKey: Bool) {
        self.allowKey = allowKey
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        animationBehavior = .none
        becomesKeyOnlyIfNeeded = !allowKey
    }

    override var canBecomeKey: Bool { allowKey }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

/// 悬浮球容器：拦截鼠标事件，区分"单击"和"拖动"
final class BallContainerView: NSView {
    var onClick: () -> Void = {}
    var onRightClick: (NSEvent) -> Void = { _ in }
    var onDragBegan: () -> Void = {}
    var onDragMoved: () -> Void = {}
    var onDragEnded: () -> Void = {}

    private var startMouse: NSPoint = .zero
    private var startOrigin: NSPoint = .zero
    private var dragging = false

    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        startMouse = NSEvent.mouseLocation
        startOrigin = window?.frame.origin ?? .zero
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        let p = NSEvent.mouseLocation
        let dx = p.x - startMouse.x, dy = p.y - startMouse.y
        if !dragging, hypot(dx, dy) < 3 { return }
        if !dragging {
            dragging = true
            onDragBegan()
        }
        window?.setFrameOrigin(NSPoint(x: startOrigin.x + dx, y: startOrigin.y + dy))
        onDragMoved()
    }

    override func mouseUp(with event: NSEvent) {
        if dragging {
            dragging = false
            onDragEnded()
        } else {
            onClick()
        }
    }

    override func rightMouseDown(with event: NSEvent) { onRightClick(event) }
}

enum Backdrop {
    /// 根据外观设置，生成带圆角的半透明背景，并把内容放进去
    static func make(style: BackdropStyle, cornerRadius: CGFloat, content: NSView) -> NSView {
        if style == .glass, #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            content.autoresizingMask = [.width, .height]
            glass.contentView = content
            return glass
        }
        if style == .clear {
            let v = NSView()
            v.wantsLayer = true
            v.layer?.cornerRadius = cornerRadius
            v.layer?.cornerCurve = .continuous
            v.layer?.masksToBounds = true
            v.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.35).cgColor
            embed(content, in: v)
            return v
        }
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        v.maskImage = roundedMask(radius: cornerRadius)
        embed(content, in: v)
        return v
    }

    private static func embed(_ content: NSView, in container: NSView) {
        content.frame = container.bounds
        content.autoresizingMask = [.width, .height]
        container.addSubview(content)
    }

    static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
