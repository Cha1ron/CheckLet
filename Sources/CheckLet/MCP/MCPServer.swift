import Foundation

/// 极简 MCP (Model Context Protocol) 服务：JSON-RPC 2.0 over stdio。
/// Claude Desktop / Claude Code / Codex / Cursor 等支持 MCP 的 AI 工具都通过
/// `CheckLet.app/Contents/MacOS/CheckLet mcp` 启动它，然后调用下面的工具管理待办。
final class MCPServer {
    static let version = "1.1.0"
    private let service = TodoService()
    private var clientName = "AI"

    func run() {
        setvbuf(stdout, nil, _IOFBF, 1 << 16)
        while let line = readLine(strippingNewline: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            guard let data = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) else {
                send(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Parse error"]])
                continue
            }
            if let batch = json as? [[String: Any]] {
                let responses = batch.compactMap(handle)
                if !responses.isEmpty { send(responses) }
            } else if let msg = json as? [String: Any], let response = handle(msg) {
                send(response)
            }
        }
    }

    private func send(_ obj: Any) {
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.withoutEscapingSlashes]) else { return }
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write("\n".data(using: .utf8)!)
    }

    private func handle(_ msg: [String: Any]) -> [String: Any]? {
        let method = msg["method"] as? String ?? ""
        guard let id = msg["id"], !(id is NSNull) else { return nil } // 通知，无需回复
        let params = msg["params"] as? [String: Any] ?? [:]

        func ok(_ result: [String: Any]) -> [String: Any] { ["jsonrpc": "2.0", "id": id, "result": result] }
        func err(_ code: Int, _ message: String) -> [String: Any] {
            ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
        }

        switch method {
        case "initialize":
            if let info = params["clientInfo"] as? [String: Any], let name = info["name"] as? String {
                clientName = name
            }
            let version = params["protocolVersion"] as? String ?? "2025-06-18"
            return ok([
                "protocolVersion": version,
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "checklet", "title": "CheckLet 待办", "version": Self.version],
                "instructions": Self.instructions,
            ])
        case "ping":
            return ok([:])
        case "tools/list":
            return ok(["tools": Self.tools])
        case "tools/call":
            let name = params["name"] as? String ?? ""
            let args = params["arguments"] as? [String: Any] ?? [:]
            do {
                let text = try call(name, args)
                return ok(["content": [["type": "text", "text": text]], "isError": false])
            } catch let e as ToolNotFound {
                return err(-32602, "Unknown tool: \(e.name)")
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                return ok(["content": [["type": "text", "text": "出错了：\(message)"]], "isError": true])
            }
        case "resources/list":
            return ok(["resources": []])
        case "prompts/list":
            return ok(["prompts": []])
        default:
            return err(-32601, "Method not found: \(method)")
        }
    }

    private struct ToolNotFound: Error { let name: String }

    private func call(_ name: String, _ a: [String: Any]) throws -> String {
        func str(_ k: String) -> String? {
            if let s = a[k] as? String { return s }
            if let n = a[k] as? NSNumber { return n.stringValue }
            return nil
        }
        func bool(_ k: String) -> Bool? {
            if let b = a[k] as? Bool { return b }
            if let s = a[k] as? String { return ["true", "1", "yes"].contains(s.lowercased()) }
            return nil
        }
        func scope(_ k: String) throws -> TodoScope? {
            guard let raw = str(k), !raw.isEmpty, raw.lowercased() != "all" else { return nil }
            guard let s = TodoScope(loose: raw) else {
                throw TodoError.invalid("list 只能是 today / week / date，收到「\(raw)」")
            }
            return s
        }

        func category(_ raw: Any?) throws -> TodoCategory? {
            guard let r = raw as? String, !r.isEmpty, r.lowercased() != "auto", r.lowercased() != "all" else { return nil }
            guard let c = TodoCategory(loose: r) else {
                throw TodoError.invalid("category 只能是 \(TodoCategory.allCases.map(\.rawValue).joined(separator: " / "))，收到「\(r)」")
            }
            return c
        }

        switch name {
        case "list_todos":
            let items = service.list(scope: try scope("list"), category: try category(a["category"]),
                                     includeDone: bool("include_done") ?? true,
                                     includeUpcoming: bool("include_upcoming") ?? false)
            return TodoFormatter.listing(items)

        case "add_todo":
            guard let title = str("title") else { throw TodoError.invalid("缺少 title") }
            let item = try service.add(title: title, scope: try scope("list") ?? .today, date: str("date"),
                                       note: str("note"), source: clientName,
                                       category: try category(a["category"]), categorySource: .ai)
            return "已添加到「\(item.scope.title)」：\n" + TodoFormatter.line(item)

        case "add_todos":
            guard let list = a["items"] as? [[String: Any]], !list.isEmpty else {
                throw TodoError.invalid("items 需要是非空数组")
            }
            var lines: [String] = []
            for entry in list {
                guard let title = entry["title"] as? String else { continue }
                let s = (entry["list"] as? String).flatMap(TodoScope.init(loose:)) ?? .today
                let item = try service.add(title: title, scope: s, date: entry["date"] as? String,
                                           note: entry["note"] as? String, source: clientName,
                                           category: try category(entry["category"]), categorySource: .ai)
                lines.append("「\(item.scope.title)」" + TodoFormatter.line(item))
            }
            return "已添加 \(lines.count) 条：\n" + lines.joined(separator: "\n")

        case "complete_todo":
            guard let ref = str("id") ?? str("title") else { throw TodoError.invalid("需要 id 或 title") }
            let done = bool("done") ?? true
            let item = try service.setDone(ref, done: done)
            return (done ? "已完成 ✅ " : "已标记为未完成：") + TodoFormatter.line(item)

        case "update_todo":
            guard let ref = str("id") else { throw TodoError.invalid("需要 id") }
            let item = try service.update(ref, title: str("title"), scope: try scope("list"),
                                          date: str("date"), note: str("note"),
                                          category: try category(a["category"]), categorySource: .ai)
            return "已更新：" + TodoFormatter.line(item)

        case "delete_todo":
            guard let ref = str("id") ?? str("title") else { throw TodoError.invalid("需要 id 或 title") }
            let item = try service.delete(ref)
            return "已删除：\(item.title)"

        default:
            throw ToolNotFound(name: name)
        }
    }

    // MARK: - 工具定义

    static let instructions = """
    CheckLet 是用户 Mac 桌面上的悬浮待办清单，分三个清单：today（今日待办）、week（本周待办）、date（重要日期，比如生日、截止日、纪念日）。
    当用户说"把…加到待办/清单/CheckLet""提醒我…""这周要…""X 月 X 日是…"时使用这些工具。
    - 今日待办：list=today；如果用户说"明天要做X"，用 list=today 并把 date 设为明天，它会在那天出现。
    - 本周待办：list=week。
    - 重要日期：list=date，必须给 date（YYYY-MM-DD）。
    未完成的今日/本周待办会自动顺延。完成或删除前如果不确定是哪一条，先调用 list_todos 拿到 id。
    每条待办都有分类 category，添加时请根据内容主动选一个最合适的：
    \(TodoCategory.allCases.map { "- \($0.rawValue)：\($0.name)（\($0.meaning)）" }.joined(separator: "\n"))
    例如"给猫换猫砂"→life，"交房租"→finance，"给妈妈买生日礼物"→social。不传 category 时会按关键词自动分类。
    用户要求"重新分类/整理分类"时，用 update_todo 逐条修改 category。
    """

    private static let categoryEnum: [String: Any] = [
        "type": "string",
        "enum": TodoCategory.allCases.map(\.rawValue),
        "description": "分类：" + TodoCategory.allCases.map { "\($0.rawValue)=\($0.name)" }.joined(separator: "，")
            + "。请根据内容选择；不确定可不传，会自动分类",
    ]

    private static let listEnum: [String: Any] = [
        "type": "string",
        "enum": ["today", "week", "date"],
        "description": "today=今日待办，week=本周待办，date=重要日期",
    ]

    static let tools: [[String: Any]] = [
        [
            "name": "list_todos",
            "title": "查看待办",
            "description": "列出用户当前的待办（今日 / 本周 / 重要日期），每条带有 6 位 id。",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "list": ["type": "string", "enum": ["today", "week", "date", "all"],
                             "description": "只看某个清单，默认 all"],
                    "category": categoryEnum,
                    "include_done": ["type": "boolean", "description": "是否包含今天已完成的，默认 true"],
                    "include_upcoming": ["type": "boolean", "description": "是否包含还没到日子的未来待办，默认 false"],
                ],
            ],
            "annotations": ["readOnlyHint": true],
        ],
        [
            "name": "add_todo",
            "title": "添加待办",
            "description": "往用户的 CheckLet 悬浮清单里添加一条待办或重要日期。",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "title": ["type": "string", "description": "待办内容，简洁明了"],
                    "list": listEnum,
                    "date": ["type": "string",
                             "description": "YYYY-MM-DD。date 清单必填；today 清单填未来日期则到那天才出现；week 清单表示那一周"],
                    "note": ["type": "string", "description": "可选备注"],
                    "category": categoryEnum,
                ],
                "required": ["title"],
            ],
        ],
        [
            "name": "add_todos",
            "title": "批量添加待办",
            "description": "一次添加多条待办，适合用户一口气列出好几件事。",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "items": [
                        "type": "array",
                        "items": [
                            "type": "object",
                            "properties": [
                                "title": ["type": "string"],
                                "list": listEnum,
                                "date": ["type": "string", "description": "YYYY-MM-DD"],
                                "note": ["type": "string"],
                                "category": categoryEnum,
                            ],
                            "required": ["title"],
                        ],
                    ],
                ],
                "required": ["items"],
            ],
        ],
        [
            "name": "complete_todo",
            "title": "完成待办",
            "description": "把一条待办标记为完成（打勾）。可以用 id，或者用标题关键字匹配。",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "id": ["type": "string", "description": "待办 id（来自 list_todos）"],
                    "title": ["type": "string", "description": "没有 id 时，用标题关键字匹配"],
                    "done": ["type": "boolean", "description": "false 表示取消打勾，默认 true"],
                ],
            ],
        ],
        [
            "name": "update_todo",
            "title": "修改待办",
            "description": "修改待办的内容、所属清单、日期、备注或分类。",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "id": ["type": "string", "description": "待办 id 或标题关键字"],
                    "title": ["type": "string"],
                    "list": listEnum,
                    "date": ["type": "string", "description": "YYYY-MM-DD"],
                    "note": ["type": "string", "description": "传空字符串可清除备注"],
                    "category": categoryEnum,
                ],
                "required": ["id"],
            ],
        ],
        [
            "name": "delete_todo",
            "title": "删除待办",
            "description": "删除一条待办。",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "id": ["type": "string", "description": "待办 id"],
                    "title": ["type": "string", "description": "没有 id 时，用标题关键字匹配"],
                ],
            ],
            "annotations": ["destructiveHint": true],
        ],
    ]
}
