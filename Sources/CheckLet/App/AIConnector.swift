import Foundation

/// 把 CheckLet 的 MCP 服务注册到各个 AI 工具里
enum AIConnector {
    static let serverName = "checklet"

    static var executablePath: String {
        (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0]))
            .resolvingSymlinksInPath().path
    }

    /// 如果 App 还在下载目录的临时位置/安装盘里运行，注册的路径之后会失效
    static var locationWarning: String? {
        let p = executablePath
        if p.contains("/AppTranslocation/") || p.hasPrefix("/Volumes/") {
            return "请先把 CheckLet 拖进「应用程序」文件夹并从那里打开，再连接 AI 工具，否则路径会失效。"
        }
        if !p.contains(".app/") {
            return "当前运行的是开发版本（未打包），连接的是：\(p)"
        }
        return nil
    }

    private static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    // MARK: 通用配置（Muse、Cursor 等任何支持 MCP 的工具）

    static var genericJSON: String {
        """
        {
          "mcpServers": {
            "\(serverName)": {
              "command": "\(jsonEscape(executablePath))",
              "args": ["mcp"]
            }
          }
        }
        """
    }

    static var cliCommand: String { "\"\(executablePath)\" add \"要做的事\"" }

    // MARK: Claude Desktop

    static var claudeDesktopConfig: URL {
        home.appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json")
    }

    static var isClaudeDesktopConnected: Bool {
        guard let root = readJSON(claudeDesktopConfig),
              let servers = root["mcpServers"] as? [String: Any],
              let me = servers[serverName] as? [String: Any] else { return false }
        return me["command"] as? String == executablePath
    }

    static func connectClaudeDesktop() throws -> String {
        let url = claudeDesktopConfig
        var root: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: url.path) {
            guard let existing = readJSON(url) else {
                throw TodoError.invalid("Claude Desktop 配置文件不是合法 JSON，为安全起见没有修改：\(url.path)")
            }
            root = existing
            backup(url)
        } else {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        var servers = root["mcpServers"] as? [String: Any] ?? [:]
        servers[serverName] = ["command": executablePath, "args": ["mcp"]]
        root["mcpServers"] = servers
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
        return "已写入 Claude Desktop 配置。请完全退出并重新打开 Claude Desktop。"
    }

    // MARK: Codex

    static var codexConfig: URL { home.appendingPathComponent(".codex/config.toml") }

    static var isCodexConnected: Bool {
        guard let text = try? String(contentsOf: codexConfig, encoding: .utf8) else { return false }
        return text.contains("[mcp_servers.\(serverName)]") && text.contains(tomlEscape(executablePath))
    }

    static func connectCodex() throws -> String {
        let url = codexConfig
        var lines: [String] = []
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            backup(url)
            lines = text.components(separatedBy: "\n")
            // 删除旧的 [mcp_servers.checklet] 段（含子表）
            let header = "[mcp_servers.\(serverName)"
            var out: [String] = []
            var skipping = false
            for line in lines {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("[") {
                    skipping = t == header + "]" || t.hasPrefix(header + ".")
                }
                if !skipping { out.append(line) }
            }
            lines = out
            while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
        } else {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        if !lines.isEmpty { lines.append("") }
        lines += [
            "[mcp_servers.\(serverName)]",
            "command = \"\(tomlEscape(executablePath))\"",
            "args = [\"mcp\"]",
            "",
        ]
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return "已写入 ~/.codex/config.toml。重新启动 Codex（CLI / App / IDE 插件）即可使用。"
    }

    // MARK: Claude Code

    static var claudeCodeCommand: String {
        "claude mcp add --scope user \(serverName) -- \"\(executablePath)\" mcp"
    }

    static var isClaudeCodeConnected: Bool {
        guard let root = readJSON(home.appendingPathComponent(".claude.json")),
              let servers = root["mcpServers"] as? [String: Any] else { return false }
        return servers[serverName] != nil
    }

    /// 调用 claude CLI 注册（需要已安装 Claude Code）
    static func connectClaudeCode() throws -> String {
        guard let cli = findClaudeCLI() else {
            throw TodoError.invalid("没找到 claude 命令。请在终端里运行下面这行：\n\(claudeCodeCommand)")
        }
        _ = run(cli, ["mcp", "remove", "--scope", "user", serverName])
        let r = run(cli, ["mcp", "add", "--scope", "user", serverName, "--", executablePath, "mcp"])
        guard r.status == 0 else {
            throw TodoError.invalid("claude 命令执行失败：\(r.output.prefix(300))\n可以在终端手动运行：\n\(claudeCodeCommand)")
        }
        return "已添加到 Claude Code（用户级，所有项目可用）。新开一个 Claude Code 会话即可使用。"
    }

    private static func findClaudeCLI() -> String? {
        let fm = FileManager.default
        var candidates = [
            "~/.claude/local/claude", "~/.local/bin/claude", "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude", "~/.npm-global/bin/claude", "~/.bun/bin/claude", "~/.volta/bin/claude",
        ].map { ($0 as NSString).expandingTildeInPath }
        let nvm = home.appendingPathComponent(".nvm/versions/node")
        if let versions = try? fm.contentsOfDirectory(atPath: nvm.path) {
            candidates += versions.sorted(by: >).map { nvm.appendingPathComponent("\($0)/bin/claude").path }
        }
        if let found = candidates.first(where: { fm.isExecutableFile(atPath: $0) }) { return found }
        let r = run("/bin/zsh", ["-lc", "command -v claude"])
        let path = r.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return r.status == 0 && fm.isExecutableFile(atPath: path) ? path : nil
    }

    // MARK: 工具函数

    @discardableResult
    private static func run(_ exe: String, _ args: [String]) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        let dir = (exe as NSString).deletingLastPathComponent
        env["PATH"] = "\(dir):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
        p.environment = env
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (-1, error.localizedDescription) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    private static func readJSON(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if data.isEmpty { return [:] }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func backup(_ url: URL) {
        let bak = url.appendingPathExtension("checklet-backup")
        try? FileManager.default.removeItem(at: bak)
        try? FileManager.default.copyItem(at: url, to: bak)
    }

    private static func jsonEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func tomlEscape(_ s: String) -> String { jsonEscape(s) }
}
