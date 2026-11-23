import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static let showNotification = Notification.Name("com.checklet.app.show")

    let vm = TodoViewModel()
    private let hotKeys = HotKeyManager()
    private let settingsModel = SettingsModel()

    private var ballPanel: FloatingPanel!
    private var listPanel: FloatingPanel!
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?

    private var hoverTimer: Timer?
    private var ballHoverSince: Date?
    private var outsideSince: Date?
    private var dragging = false
    private var hideGeneration = 0

    private var appliedStyle: BackdropStyle?
    private var appliedHotKey: HotKeyPreset?
    private var appliedOpacity: Double = 1

    private let ballSize: CGFloat = 52
    private let panelSize = NSSize(width: 340, height: 500)
    private let gap: CGFloat = 10

    // MARK: - 启动

    func applicationDidFinishLaunching(_ notification: Notification) {
        Prefs.registerDefaults()

        vm.onTogglePin = { [weak self] in self?.togglePinButton() }
        vm.onOpenSettings = { [weak self] in self?.openSettings(tab: 0) }
        vm.onClose = { [weak self] in self?.unpinAndHide() }

        ballPanel = FloatingPanel(contentRect: NSRect(origin: savedBallOrigin(), size: NSSize(width: ballSize, height: ballSize)),
                                  allowKey: false)
        listPanel = FloatingPanel(contentRect: NSRect(origin: .zero, size: panelSize), allowKey: true)
        listPanel.delegate = self
        listPanel.onEscape = { [weak self] in self?.unpinAndHide() }

        applyPrefs(force: true)
        buildStatusItem()

        if UserDefaults.standard.bool(forKey: Prefs.showBall) { ballPanel.orderFrontRegardless() }
        if vm.pinned { showPanel(focus: false) }

        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in self?.tick() }
        hoverTimer?.tolerance = 0.02

        NotificationCenter.default.addObserver(self, selector: #selector(defaultsChanged),
                                               name: UserDefaults.didChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(showFromOtherInstance),
                                                            name: Self.showNotification, object: nil)

        if let dir = ProcessInfo.processInfo.environment["CHECKLET_SNAPSHOT"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.writeSnapshots(to: dir) }
        }
    }

    /// 调试用：把悬浮球和面板渲染成 PNG（CHECKLET_SNAPSHOT=目录）
    private func writeSnapshots(to dir: String) {
        for (name, window) in [("ball", ballPanel!), ("panel", listPanel!)] {
            guard let view = window.contentView, window.isVisible else { continue }
            for tab in TodoScope.allCases where name == "panel" || tab == .today {
                vm.tab = tab
                view.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
                guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: rep)
                let file = URL(fileURLWithPath: dir).appendingPathComponent("\(name)-\(tab.rawValue).png")
                try? rep.representation(using: .png, properties: [:])?.write(to: file)
            }
        }
        vm.tab = .today
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        pinAndShow(focus: true)
        return false
    }

    @objc private func showFromOtherInstance() { pinAndShow(focus: true) }

    // MARK: - 偏好设置

    @objc private func defaultsChanged() {
        DispatchQueue.main.async { self.applyPrefs(force: false) }
    }

    private func applyPrefs(force: Bool) {
        let style = BackdropStyle.current
        if force || style != appliedStyle {
            appliedStyle = style
            installContent(style: style)
        }
        let preset = HotKeyPreset.current
        if force || preset != appliedHotKey {
            appliedHotKey = preset
            hotKeys.register(preset) { [weak self] in self?.hotKeyPressed() }
            updateMenuShortcutTitle()
        }
        let opacity = UserDefaults.standard.double(forKey: Prefs.opacity)
        if opacity != appliedOpacity {
            appliedOpacity = max(0.3, min(1, opacity))
            if listPanel.isVisible { listPanel.alphaValue = appliedOpacity }
        }
        let showBall = UserDefaults.standard.bool(forKey: Prefs.showBall)
        if showBall && !ballPanel.isVisible { ballPanel.orderFrontRegardless() }
        if !showBall && ballPanel.isVisible { ballPanel.orderOut(nil) }
    }

    private func installContent(style: BackdropStyle) {
        // 悬浮球
        let container = BallContainerView(frame: NSRect(origin: .zero, size: NSSize(width: ballSize, height: ballSize)))
        container.onClick = { [weak self] in self?.ballClicked() }
        container.onRightClick = { [weak self] event in
            guard let self, let view = self.ballPanel.contentView else { return }
            NSMenu.popUpContextMenu(self.makeMenu(), with: event, for: view)
        }
        container.onDragBegan = { [weak self] in self?.dragging = true }
        container.onDragMoved = { [weak self] in
            guard let self, self.listPanel.isVisible else { return }
            self.positionPanel()
        }
        container.onDragEnded = { [weak self] in self?.ballDragEnded() }
        let ballHost = NSHostingView(rootView: BallView(vm: vm, size: ballSize))
        let ballBackdrop = Backdrop.make(style: style, cornerRadius: ballSize / 2, content: ballHost)
        ballBackdrop.frame = container.bounds
        ballBackdrop.autoresizingMask = [.width, .height]
        container.addSubview(ballBackdrop)
        ballPanel.contentView = container

        // 待办面板
        let panelHost = NSHostingView(rootView: PanelView(vm: vm))
        let panelBackdrop = Backdrop.make(style: style, cornerRadius: 18, content: panelHost)
        panelBackdrop.frame = NSRect(origin: .zero, size: panelSize)
        listPanel.contentView = panelBackdrop
        ballPanel.invalidateShadow()
        listPanel.invalidateShadow()
    }

    // MARK: - 显示 / 隐藏

    private func tick() {
        guard !dragging else { return }
        let p = NSEvent.mouseLocation
        let now = Date()
        let ballFrame = ballPanel.frame.insetBy(dx: -2, dy: -2)
        let inBall = ballPanel.isVisible && ballFrame.contains(p)

        if !listPanel.isVisible {
            outsideSince = nil
            if inBall {
                if let since = ballHoverSince {
                    if now.timeIntervalSince(since) > 0.15 { showPanel(focus: false) }
                } else {
                    ballHoverSince = now
                }
            } else {
                ballHoverSince = nil
            }
            return
        }
        ballHoverSince = nil

        // 固定 / 正在面板里输入 → 不自动隐藏
        if vm.pinned || listPanel.isKeyWindow {
            outsideSince = nil
            return
        }
        if isInsideHoverZone(p) {
            outsideSince = nil
        } else if let since = outsideSince {
            if now.timeIntervalSince(since) > 0.35 { hidePanel() }
        } else {
            outsideSince = now
        }
    }

    /// 悬浮球 + 面板 + 两者之间的"走廊"
    private func isInsideHoverZone(_ p: NSPoint) -> Bool {
        let ball = ballPanel.frame
        let panel = listPanel.frame
        if panel.insetBy(dx: -8, dy: -8).contains(p) { return true }
        if ballPanel.isVisible {
            if ball.insetBy(dx: -4, dy: -4).contains(p) { return true }
            let union = ball.union(panel)
            let corridor = NSRect(x: union.minX, y: ball.minY - 4, width: union.width, height: ball.height + 8)
            if corridor.contains(p) { return true }
        }
        return false
    }

    func showPanel(focus: Bool) {
        hideGeneration += 1
        positionPanel()
        if !listPanel.isVisible {
            listPanel.alphaValue = 0
            listPanel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.14
            listPanel.animator().alphaValue = appliedOpacity
        }
        if focus {
            listPanel.makeKeyAndOrderFront(nil)
            vm.focusToken += 1
        }
        outsideSince = nil
    }

    func hidePanel() {
        guard listPanel.isVisible else { return }
        hideGeneration += 1
        let generation = hideGeneration
        if listPanel.isKeyWindow { listPanel.resignKey() }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.16
            listPanel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, generation == self.hideGeneration else { return }
            self.listPanel.orderOut(nil)
        })
    }

    private func positionPanel() {
        let size = panelSize
        let screen = (ballPanel.isVisible ? ballPanel.screen : nil) ?? NSScreen.main ?? NSScreen.screens[0]
        let vf = screen.visibleFrame
        var origin: NSPoint
        if ballPanel.isVisible {
            let b = ballPanel.frame
            let x = b.midX > vf.midX ? b.minX - gap - size.width : b.maxX + gap
            origin = NSPoint(x: x, y: b.maxY - size.height)
        } else {
            // 没有悬浮球时，显示在屏幕右上角
            origin = NSPoint(x: vf.maxX - size.width - 16, y: vf.maxY - size.height - 16)
        }
        origin.x = min(max(origin.x, vf.minX + 8), vf.maxX - size.width - 8)
        origin.y = min(max(origin.y, vf.minY + 8), vf.maxY - size.height - 8)
        listPanel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private func ballClicked() {
        if !listPanel.isVisible {
            vm.pinned = true
            showPanel(focus: false)
        } else if !vm.pinned {
            vm.pinned = true
        } else {
            unpinAndHide()
        }
    }

    private func hotKeyPressed() {
        if listPanel.isVisible && vm.pinned && listPanel.isKeyWindow {
            unpinAndHide()
        } else {
            pinAndShow(focus: true)
        }
    }

    private func togglePinButton() {
        vm.pinned.toggle()
        outsideSince = nil
    }

    func pinAndShow(focus: Bool) {
        vm.pinned = true
        showPanel(focus: focus)
    }

    func unpinAndHide() {
        vm.pinned = false
        hidePanel()
    }

    @objc private func toggleFromMenu() {
        if listPanel.isVisible { unpinAndHide() } else { pinAndShow(focus: true) }
    }

    func windowDidResignKey(_ notification: Notification) {
        guard (notification.object as? NSWindow) === listPanel, !vm.pinned else { return }
        if !isInsideHoverZone(NSEvent.mouseLocation) { hidePanel() }
    }

    // MARK: - 悬浮球位置

    private func savedBallOrigin() -> NSPoint {
        let d = UserDefaults.standard
        if d.object(forKey: Prefs.ballX) != nil {
            let p = NSPoint(x: d.double(forKey: Prefs.ballX), y: d.double(forKey: Prefs.ballY))
            if NSScreen.screens.contains(where: { $0.visibleFrame.insetBy(dx: -10, dy: -10).contains(p) }) { return p }
        }
        let vf = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        return NSPoint(x: vf.maxX - ballSize - 12, y: vf.midY + 80)
    }

    private func ballDragEnded() {
        dragging = false
        guard let screen = ballPanel.screen ?? NSScreen.main else { return }
        let vf = screen.visibleFrame
        var f = ballPanel.frame
        // 靠近屏幕边缘时自动吸附
        if f.minX - vf.minX < 40 { f.origin.x = vf.minX + 8 }
        if vf.maxX - f.maxX < 40 { f.origin.x = vf.maxX - f.width - 8 }
        f.origin.x = min(max(f.origin.x, vf.minX + 2), vf.maxX - f.width - 2)
        f.origin.y = min(max(f.origin.y, vf.minY + 2), vf.maxY - f.height - 2)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ballPanel.animator().setFrame(f, display: true)
        }
        UserDefaults.standard.set(Double(f.origin.x), forKey: Prefs.ballX)
        UserDefaults.standard.set(Double(f.origin.y), forKey: Prefs.ballY)
        if listPanel.isVisible {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { self.positionPanel() }
        }
    }

    @objc private func screensChanged() {
        let origin = savedBallOrigin()
        ballPanel.setFrameOrigin(origin)
        if listPanel.isVisible { positionPanel() }
    }

    // MARK: - 菜单栏

    private var toggleMenuItem: NSMenuItem?

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "CheckLet")
            button.image?.isTemplate = true
        }
        statusItem.menu = makeMenu()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let toggle = NSMenuItem(title: "显示 / 隐藏待办", action: #selector(toggleFromMenu), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        toggleMenuItem = toggle
        updateMenuShortcutTitle()

        let showBall = NSMenuItem(title: "显示悬浮球", action: #selector(toggleBall), keyEquivalent: "")
        showBall.target = self
        showBall.state = UserDefaults.standard.bool(forKey: Prefs.showBall) ? .on : .off
        menu.addItem(showBall)

        menu.addItem(.separator())
        let settings = NSMenuItem(title: "设置…", action: #selector(openSettingsMenu), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let ai = NSMenuItem(title: "连接 AI 工具…", action: #selector(openAISettings), keyEquivalent: "")
        ai.target = self
        menu.addItem(ai)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 CheckLet", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    private func updateMenuShortcutTitle() {
        let preset = HotKeyPreset.current
        toggleMenuItem?.title = preset == .off ? "显示 / 隐藏待办" : "显示 / 隐藏待办（\(preset.title)）"
    }

    @objc private func toggleBall() {
        let d = UserDefaults.standard
        d.set(!d.bool(forKey: Prefs.showBall), forKey: Prefs.showBall)
        statusItem.menu = makeMenu()
    }

    @objc private func openSettingsMenu() { openSettings(tab: 0) }
    @objc private func openAISettings() { openSettings(tab: 1) }

    func openSettings(tab: Int) {
        settingsModel.tab = tab
        if settingsWindow == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: settingsModel)))
            w.title = "CheckLet 设置"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
