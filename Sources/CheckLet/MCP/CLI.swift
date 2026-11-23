import Foundation

/// 命令行：方便能执行 shell 命令、但不支持 MCP 的 AI 工具或脚本使用。
///   CheckLet list [today|week|date]
///   CheckLet add "写周报" [--week | --date 2026-12-01 | --on tomorrow] [--note "..."]
///   CheckLet done <id或标题> / undo <id> / rm <id>
enum CLI {
    static let commands: Set<String> = ["list", "ls", "add", "done", "undo", "rm", "delete", "help", "--help", "-h", "version", "--version"]

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
                let scope = rest.first.flatMap(TodoScope.init(loose:))
                print(TodoFormatter.listing(service.list(scope: scope, includeUpcoming: flag("--all", "-a"))), terminator: "")
            case "add":
                let note = option("--note", "-n")
                var scope: TodoScope = .today
                var date: String?
                if let d = option("--date", "-d") { scope = .date; date = d }
                if let d = option("--on") { date = d }
                if flag("--week", "-w") { scope = .week }
                if flag("--today", "-t") { scope = .today }
                let title = rest.joined(separator: " ")
                let item = try service.add(title: title, scope: scope, date: date, note: note, source: "cli")
                print("已添加到「\(item.scope.title)」: " + TodoFormatter.line(item))
            case "done", "undo":
                let item = try service.setDone(rest.joined(separator: " "), done: cmd == "done")
                print(TodoFormatter.line(item))
            case "rm", "delete":
                let item = try service.delete(rest.joined(separator: " "))
                print("已删除: \(item.title)")
            case "version", "--version":
                print("CheckLet \(MCPServer.version)")
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
      CheckLet list [today|week|date]  查看待办（-a 包含未来的）
      CheckLet add <内容> [选项]        添加待办
          --week, -w                   加到本周
          --date, -d <日期>            加到重要日期，如 2026-12-01 / 12-01 / 明天
          --on <日期>                  今日待办在指定那天出现
          --note, -n <备注>
      CheckLet done <id或标题>          打勾
      CheckLet undo <id或标题>          取消打勾
      CheckLet rm <id或标题>            删除
    """
}
