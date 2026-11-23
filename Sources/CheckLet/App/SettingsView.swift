import AppKit
import ServiceManagement
import SwiftUI

final class SettingsModel: ObservableObject {
    @Published var tab = 0
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        TabView(selection: $model.tab) {
            GeneralSettings()
                .tabItem { Label("通用", systemImage: "gearshape") }
                .tag(0)
            AISettings()
                .tabItem { Label("AI 连接", systemImage: "sparkles") }
                .tag(1)
            AboutView()
                .tabItem { Label("关于", systemImage: "info.circle") }
                .tag(2)
        }
        .frame(width: 560, height: 520)
    }
}

// MARK: - 通用

struct GeneralSettings: View {
    @AppStorage(Prefs.opacity) private var opacity = 1.0
    @AppStorage(Prefs.style) private var style = BackdropStyle.frosted.rawValue
    @AppStorage(Prefs.hotKey) private var hotKey = HotKeyPreset.ctrlOptT.rawValue
    @AppStorage(Prefs.showBall) private var showBall = true
    @State private var launchAtLogin = false
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("外观") {
                Picker("面板样式", selection: $style) {
                    ForEach(BackdropStyle.allCases) { s in
                        Text(s.title).tag(s.rawValue)
                    }
                }
                HStack {
                    Text("不透明度")
                    Slider(value: $opacity, in: 0.5...1.0)
                    Text("\(Int(opacity * 100))%").monospacedDigit().frame(width: 40, alignment: .trailing)
                }
                Toggle("显示悬浮球（关闭后可用快捷键或菜单栏图标打开）", isOn: $showBall)
            }
            Section("快捷键") {
                Picker("显示 / 隐藏面板", selection: $hotKey) {
                    ForEach(HotKeyPreset.allCases) { p in
                        Text(p.title).tag(p.rawValue)
                    }
                }
                Text("按快捷键会固定显示面板并聚焦输入框，再按一次隐藏。Esc 也可隐藏。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("启动") {
                Toggle("开机自动启动", isOn: Binding(
                    get: { launchAtLogin },
                    set: { setLaunchAtLogin($0) }))
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }
            Section("数据") {
                HStack {
                    Text(TodoStore.shared.fileURL.path)
                        .font(.caption).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                    Spacer()
                    Button("在访达中显示") {
                        NSWorkspace.shared.activateFileViewerSelecting([TodoStore.shared.fileURL])
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { launchAtLogin = SMAppService.mainApp.status == .enabled }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "设置失败：\(error.localizedDescription)（请确认 App 已放在「应用程序」文件夹）"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

// MARK: - AI 连接

struct AISettings: View {
    @State private var messages: [String: (ok: Bool, text: String)] = [:]
    @State private var busy: String?
    @State private var refresh = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("连接后，你可以直接对 AI 说：「把明天下午交报告加到我的待办」「这周要做的事有哪些？」「把买牛奶打勾」。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let warn = AIConnector.locationWarning {
                    Label(warn, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ToolCard(id: "desktop", name: "Claude Desktop", icon: "bubble.left.and.text.bubble.right",
                         detail: "写入 claude_desktop_config.json",
                         connected: AIConnector.isClaudeDesktopConnected, busy: busy, message: messages["desktop"]) {
                    connect("desktop") { try AIConnector.connectClaudeDesktop() }
                }
                ToolCard(id: "code", name: "Claude Code", icon: "terminal",
                         detail: "通过 claude mcp add 注册为用户级 MCP",
                         connected: AIConnector.isClaudeCodeConnected, busy: busy, message: messages["code"]) {
                    connect("code") { try AIConnector.connectClaudeCode() }
                }
                ToolCard(id: "codex", name: "Codex", icon: "chevron.left.forwardslash.chevron.right",
                         detail: "写入 ~/.codex/config.toml（CLI、App、IDE 插件共用）",
                         connected: AIConnector.isCodexConnected, busy: busy, message: messages["codex"]) {
                    connect("codex") { try AIConnector.connectCodex() }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label("Muse 及其他支持 MCP 的工具（Cursor、Windsurf、Cherry Studio…）", systemImage: "puzzlepiece.extension")
                        .font(.headline)
                    Text("在该工具的 MCP 设置里添加一个 stdio 服务器，粘贴下面的配置：")
                        .font(.caption).foregroundStyle(.secondary)
                    CopyBox(text: AIConnector.genericJSON)
                    Text("如果工具只能执行命令行，也可以用：")
                        .font(.caption).foregroundStyle(.secondary)
                    CopyBox(text: AIConnector.cliCommand)
                }
                .padding(14)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            }
            .padding(20)
            .id(refresh)
        }
    }

    private func connect(_ key: String, _ action: @escaping () throws -> String) {
        busy = key
        DispatchQueue.global(qos: .userInitiated).async {
            let result: (Bool, String)
            do { result = (true, try action()) } catch {
                result = (false, (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
            DispatchQueue.main.async {
                messages[key] = result
                busy = nil
                refresh += 1
            }
        }
    }
}

struct ToolCard: View {
    let id: String
    let name: String
    let icon: String
    let detail: String
    let connected: Bool
    let busy: String?
    let message: (ok: Bool, text: String)?
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.headline)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if connected {
                    Label("已连接", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.green)
                }
                if busy == id {
                    ProgressView().controlSize(.small)
                } else {
                    Button(connected ? "重新连接" : "一键连接", action: action)
                }
            }
            if let message {
                Text(message.text)
                    .font(.caption)
                    .foregroundStyle(message.ok ? Color.green : Color.red)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct CopyBox: View {
    let text: String
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top) {
            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(copied ? "已复制" : "复制") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - 关于

struct AboutView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)
            Text("CheckLet").font(.title.bold())
            Text("版本 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? MCPServer.version)")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                Text("• 鼠标移到悬浮球上 → 显示待办")
                Text("• 点击悬浮球 / 按快捷键 → 固定显示")
                Text("• 拖动悬浮球可以换位置，右键有更多选项")
                Text("• 双击待办可编辑，右键可推迟 / 移动 / 删除")
                Text("• 未完成的今日待办会自动顺延到第二天")
            }
            .font(.callout)
            .padding(.top, 8)
            Spacer()
        }
        .padding(30)
    }
}
