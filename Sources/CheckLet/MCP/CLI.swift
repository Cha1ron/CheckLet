import AppKit
import Foundation

/// 命令行：方便能执行 shell 命令、但不支持 MCP 的 AI 工具或脚本使用。
///   CheckLet list [today|week|date]
///   CheckLet add "写周报" [--week | --date 2026-12-01 | --on tomorrow] [--note "..."]
///   CheckLet done <id或标题> / undo <id> / rm <id>
enum CLI {
    static let commands: Set<String> = ["list", "ls", "add", "done", "undo", "rm", "delete", "update",
                                        "help", "--help", "-h", "version", "--version"]

    static func run(_ args: [String]) -> Int32 {
        let service = TodoService()
        guard let cmd = args.first else { return 1 }
        var rest = Array(args.dropFirst())

        func option(_ names: String...) -> String? {
            for n in names {
                if let i = rest.firstIndex(of: n), i + 1 < rest.count {
                    let v = rest[i + 1]
                    rest.removeSubrange(i...(i + 1))
                    return v
                }
            }
            return nil
        }
        func flag(_ names: String...) -> Bool {
            for n in names {
                if let i = rest.firstIndex(of: n) {
                    rest.remove(at: i)
                    return true
                }
            }
            return false
        }

        do {
            switch cmd {
            case "list", "ls":
                let all = flag("--all", "-a")
                let cat = option("--cat", "-c").flatMap(TodoCategory.init(loose:))
                let scope = rest.first.flatMap(TodoScope.init(loose:))
                print(TodoFormatter.listing(service.list(scope: scope, category: cat, includeUpcoming: all)), terminator: "")
            case "add":
                let note = option("--note", "-n")
                var category: TodoCategory?
                if let raw = option("--cat", "-c") {
                    guard let c = TodoCategory(loose: raw) else { throw TodoError.invalid("未知分类：\(raw)") }
                    category = c
                }
                var scope: TodoScope = .today
                var date: String?
                if let d = option("--date", "-d") { scope = .date; date = d }
                if let d = option("--on") { date = d }
                if flag("--week", "-w") { scope = .week }
                if flag("--today", "-t") { scope = .today }
                let title = rest.joined(separator: " ")
                let item = try service.add(title: title, scope: scope, date: date, note: note, source: "cli",
                                           category: category)
                print("已添加到「\(item.scope.title)」: " + TodoFormatter.line(item))
            case "done", "undo":
                let item = try service.setDone(rest.joined(separator: " "), done: cmd == "done")
                print(TodoFormatter.line(item))
            case "rm", "delete":
                let item = try service.delete(rest.joined(separator: " "))
                print("已删除: \(item.title)")
            case "update":
                return runUpdate(checkOnly: flag("--check"), relaunch: !flag("--no-relaunch"))
            case "version", "--version":
                print("CheckLet \(Updater.currentVersion)")
            default:
                print(help)
            }
            return 0
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
            return 1
        }
    }

    static let help = """
    CheckLet — 悬浮待办

    用法:
      CheckLet                         启动悬浮球
      CheckLet mcp                     以 MCP 服务方式运行（给 AI 工具用）
      CheckLet list [today|week|date]  查看待办（-a 包含未来的，-c 生活 只看某分类）
      CheckLet add <内容> [选项]        添加待办
          --week, -w                   加到本周
          --date, -d <日期>            加到重要日期，如 2026-12-01 / 12-01 / 明天
          --on <日期>                  今日待办在指定那天出现
          --note, -n <备注>
          --cat, -c <分类>              工作/学习/生活/健康/财务/人情/其他（不填自动分类，
                                       也可以在内容里写 #生活）
      CheckLet done <id或标题>          打勾
      CheckLet undo <id或标题>          取消打勾
      CheckLet rm <id或标题>            删除
      CheckLet update [--check]        检查并安装新版本（--check 只检查，
                                       --no-relaunch 不重启正在运行的 CheckLet）
    """

    private final class Box: @unchecked Sendable { var code: Int32 = 0 }

    static func runUpdate(checkOnly: Bool, relaunch: Bool) -> Int32 {
        let box = Box()
        let done = DispatchSemaphore(value: 0)
        Task {
            defer { done.signal() }
            do {
                let info = try await Updater.fetchLatest()
                print("当前版本 \(Updater.currentVersion)，最新版本 \(info.version)")
                guard Updater.isNewer(info.version, than: Updater.currentVersion) else {
                    print("已经是最新版本 ✅")
                    return
                }
                if checkOnly { print("运行 CheckLet update 即可更新：\(info.pageURL.absoluteString)"); return }
                try Updater.checkInstallLocation()
                print("下载并校验 \(info.version)…")
                let app = try await Updater.prepare(info) { _ in }
                // 默认：关掉正在运行的悬浮球，替换完成后再打开；--no-relaunch 只替换文件，下次启动生效
                let me = ProcessInfo.processInfo.processIdentifier
                let running = relaunch
                    ? NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
                        .filter { $0.processIdentifier != me && $0.bundleURL == Bundle.main.bundleURL }
                    : []
                running.forEach { $0.terminate() }
                try Updater.launchReplacer(newApp: app, waitFor: [me] + running.map(\.processIdentifier),
                                           relaunch: relaunch)
                print("校验通过，正在安装 \(info.version)\(relaunch ? "，完成后会自动打开" : "（下次启动生效）")")
            } catch {
                FileHandle.standardError.write((Updater.describe(error) + "\n").data(using: .utf8)!)
                box.code = 1
            }
        }
        done.wait()
        return box.code
    }
}
