import AppKit

let argv = Array(CommandLine.arguments.dropFirst())

// 1) AI 工具通过 `CheckLet mcp` 启动 MCP 服务
if argv.first == "mcp" {
    MCPServer().run()
    exit(0)
}

// 2) 命令行用法
if let first = argv.first, CLI.commands.contains(first) {
    exit(CLI.run(argv))
}

// 3) 悬浮球 App（只允许运行一个实例；重复打开时让已有实例弹出面板）
if let bundleID = Bundle.main.bundleIdentifier {
    let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
    if !others.isEmpty {
        DistributedNotificationCenter.default().postNotificationName(
            AppDelegate.showNotification, object: nil, userInfo: nil, deliverImmediately: true)
        exit(0)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
