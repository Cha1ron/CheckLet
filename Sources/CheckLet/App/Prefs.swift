import AppKit
import Carbon.HIToolbox

enum Prefs {
    static let opacity = "panelOpacity"        // Double 0.5...1
    static let style = "backdropStyle"         // BackdropStyle.rawValue
    static let hotKey = "hotKeyPreset"         // HotKeyPreset.rawValue
    static let showBall = "showBall"           // Bool
    static let pinned = "panelPinned"          // Bool
    static let ballX = "ballX"
    static let ballY = "ballY"
    static let autoUpdate = "autoCheckUpdates"     // Bool
    static let lastUpdateCheck = "lastUpdateCheck" // Date
    static let skippedVersion = "skippedVersion"   // String
    static let calendarSync = "calendarSync"       // Bool
    static let calendarID = "calendarID"           // String

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            opacity: 1.0,
            style: BackdropStyle.frosted.rawValue,
            hotKey: HotKeyPreset.ctrlOptT.rawValue,
            showBall: true,
            pinned: false,
            autoUpdate: true,
        ])
    }
}

enum BackdropStyle: String, CaseIterable, Identifiable {
    case frosted
    case glass
    case clear

    var id: String { rawValue }
    var title: String {
        switch self {
        case .frosted: return "磨砂玻璃"
        case .glass: return "液态玻璃（macOS 26+）"
        case .clear: return "高透明"
        }
    }

    static var current: BackdropStyle {
        BackdropStyle(rawValue: UserDefaults.standard.string(forKey: Prefs.style) ?? "") ?? .frosted
    }
}

enum HotKeyPreset: String, CaseIterable, Identifiable {
    case ctrlOptT, optCmdT, ctrlOptSpace, ctrlShiftT, ctrlOptCmdT, off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ctrlOptT: return "⌃⌥T"
        case .optCmdT: return "⌥⌘T"
        case .ctrlOptSpace: return "⌃⌥Space"
        case .ctrlShiftT: return "⌃⇧T"
        case .ctrlOptCmdT: return "⌃⌥⌘T"
        case .off: return "不使用快捷键"
        }
    }

    var keyCode: UInt32? {
        switch self {
        case .ctrlOptSpace: return UInt32(kVK_Space)
        case .off: return nil
        default: return UInt32(kVK_ANSI_T)
        }
    }

    var carbonModifiers: UInt32 {
        switch self {
        case .ctrlOptT, .ctrlOptSpace: return UInt32(controlKey | optionKey)
        case .optCmdT: return UInt32(optionKey | cmdKey)
        case .ctrlShiftT: return UInt32(controlKey | shiftKey)
        case .ctrlOptCmdT: return UInt32(controlKey | optionKey | cmdKey)
        case .off: return 0
        }
    }

    static var current: HotKeyPreset {
        HotKeyPreset(rawValue: UserDefaults.standard.string(forKey: Prefs.hotKey) ?? "") ?? .ctrlOptT
    }
}

/// 全局快捷键（Carbon RegisterEventHotKey，不需要辅助功能权限）
final class HotKeyManager {
    private var ref: EventHotKeyRef?
    private var handlerInstalled = false
    fileprivate static var action: (() -> Void)?

    func register(_ preset: HotKeyPreset, action: @escaping () -> Void) {
        unregister()
        HotKeyManager.action = action
        guard let code = preset.keyCode else { return }
        if !handlerInstalled {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { HotKeyManager.action?() }
                return noErr
            }, 1, &spec, nil, nil)
            handlerInstalled = true
        }
        let id = EventHotKeyID(signature: OSType(0x434B_4C54), id: 1) // 'CKLT'
        let status = RegisterEventHotKey(code, preset.carbonModifiers, id, GetApplicationEventTarget(), 0, &ref)
        if status != noErr {
            NSLog("CheckLet: 快捷键 \(preset.title) 注册失败（可能被其他应用占用）: \(status)")
        }
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }
}
