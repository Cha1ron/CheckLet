import Foundation

enum TodoError: LocalizedError {
    case notFound(String)
    case ambiguous(String, [TodoItem])
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .notFound(let ref):
            return "找不到待办「\(ref)」。可以先调用 list_todos 查看 id。"
        case .ambiguous(let ref, let items):
            let lines = items.prefix(8).map { "  - (\($0.id)) \($0.title)" }.joined(separator: "\n")
            return "「\(ref)」匹配到多条待办，请用 id 指定：\n\(lines)"
        case .invalid(let msg):
            return msg
        }
    }
}

/// UI、MCP、命令行共用的业务逻辑
struct TodoService {
    var store: TodoStore = .shared

    // MARK: 查询

    func list(scope: TodoScope?, includeDone: Bool = true, includeUpcoming: Bool = false) -> [TodoItem] {
        let all = store.load()
        let today = Day.today
        let scopes = scope.map { [$0] } ?? TodoScope.allCases
        var result: [TodoItem] = []
        for s in scopes {
            var items = all.visible(s, today: today)
            if includeUpcoming {
                let upcoming = all.filter { $0.scope == s && !$0.done && !$0.isVisible(today: today) }
                    .sorted { $0.day < $1.day }
                items += upcoming
            }
            if !includeDone { items = items.filter { !$0.done } }
            result += items
        }
        return result
    }

    // MARK: 修改

    @discardableResult
    func add(title rawTitle: String, scope: TodoScope = .today, date: String? = nil,
             note: String? = nil, source: String? = nil) throws -> TodoItem {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw TodoError.invalid("待办内容不能为空") }
        let parsed = try parseDate(date)

        let day: String
        switch scope {
        case .today: day = parsed ?? Day.today
        case .week: day = Day.weekStart(of: parsed ?? Day.today)
        case .date:
            guard let parsed else { throw TodoError.invalid("重要日期需要提供 date（格式 YYYY-MM-DD）") }
            day = parsed
        }

        return try store.mutate { items in
            let ids = Set(items.map(\.id))
            var id = Self.newID()
            while ids.contains(id) { id = Self.newID() }
            let item = TodoItem(id: id, title: title, scope: scope, day: day,
                                note: note?.nilIfBlank, source: source?.nilIfBlank)
            items.append(item)
            return item
        }
    }

    @discardableResult
    func setDone(_ ref: String, done: Bool = true) throws -> TodoItem {
        try store.mutate { items in
            let i = try Self.resolve(ref, in: items, preferUndone: done)
            items[i].done = done
            items[i].doneAt = done ? Date() : nil
            return items[i]
        }
    }

    @discardableResult
    func toggle(id: String) throws -> TodoItem {
        try store.mutate { items in
            let i = try Self.resolve(id, in: items)
            items[i].done.toggle()
            items[i].doneAt = items[i].done ? Date() : nil
            return items[i]
        }
    }

    @discardableResult
    func update(_ ref: String, title: String? = nil, scope: TodoScope? = nil,
                date: String? = nil, note: String? = nil) throws -> TodoItem {
        let parsed = try parseDate(date)
        return try store.mutate { items in
            let i = try Self.resolve(ref, in: items)
            if let t = title?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { items[i].title = t }
            if let note { items[i].note = note.nilIfBlank }
            let newScope = scope ?? items[i].scope
            if scope != nil || parsed != nil {
                switch newScope {
                case .today: items[i].day = parsed ?? (scope != nil ? Day.today : items[i].day)
                case .week: items[i].day = Day.weekStart(of: parsed ?? (scope != nil ? Day.today : items[i].day))
                case .date:
                    guard let d = parsed ?? (items[i].scope == .date ? items[i].day : nil) else {
                        throw TodoError.invalid("移到「重要日期」需要提供 date（YYYY-MM-DD）")
                    }
                    items[i].day = d
                }
                items[i].scope = newScope
            }
            return items[i]
        }
    }

    @discardableResult
    func delete(_ ref: String) throws -> TodoItem {
        try store.mutate { items in
            let i = try Self.resolve(ref, in: items)
            return items.remove(at: i)
        }
    }

    /// 清理已完成且已经不显示的旧条目
    @discardableResult
    func purgeOldCompleted() throws -> Int {
        try store.mutate { items in
            let before = items.count
            items.removeAll { $0.done && !$0.isVisible() }
            return before - items.count
        }
    }

    // MARK: 工具

    private func parseDate(_ raw: String?) throws -> String? {
        guard let raw, !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        guard let d = Day.parse(raw) else {
            throw TodoError.invalid("无法识别日期「\(raw)」，请使用 YYYY-MM-DD 格式")
        }
        return d
    }

    static func newID() -> String {
        String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(6)).lowercased()
    }

    /// 通过 id、id 前缀或标题找到条目
    static func resolve(_ rawRef: String, in items: [TodoItem], preferUndone: Bool = false) throws -> Int {
        let ref = rawRef.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ref.isEmpty else { throw TodoError.invalid("需要提供待办的 id 或标题") }
        let lower = ref.lowercased()

        if let i = items.firstIndex(where: { $0.id == lower }) { return i }

        func pick(_ idx: [Int]) throws -> Int? {
            if idx.count == 1 { return idx[0] }
            if idx.count > 1 {
                // 多条同名时优先挑"当前可见"且符合完成状态的
                let narrowed = idx.filter { items[$0].isVisible() && (!preferUndone || !items[$0].done) }
                if narrowed.count == 1 { return narrowed[0] }
                throw TodoError.ambiguous(ref, (narrowed.isEmpty ? idx : narrowed).map { items[$0] })
            }
            return nil
        }

        let byPrefix = items.indices.filter { items[$0].id.hasPrefix(lower) }
        if lower.count >= 3, let i = try pick(byPrefix) { return i }

        let exact = items.indices.filter { items[$0].title.lowercased() == lower }
        if let i = try pick(exact) { return i }

        let contains = items.indices.filter { items[$0].title.lowercased().contains(lower) }
        if let i = try pick(contains) { return i }

        throw TodoError.notFound(ref)
    }
}

enum TodoFormatter {
    static func line(_ t: TodoItem, today: String = Day.today) -> String {
        var s = "\(t.done ? "[x]" : "[ ]") (\(t.id)) \(t.title)"
        var meta: [String] = []
        switch t.scope {
        case .today:
            if t.day > today { meta.append("\(t.day) 起") }
            else if t.isCarriedOver(today: today) { meta.append("从 \(t.day) 顺延") }
        case .week:
            if t.day > Day.weekStart(of: today) { meta.append("\(t.day) 那周") }
            else if t.isCarriedOver(today: today) { meta.append("上周遗留") }
        case .date:
            meta.append("\(t.day) \(Day.weekdayName(t.day))，\(t.countdownText(today: today))")
        }
        if let n = t.note { meta.append("备注: \(n)") }
        if let src = t.sourceLabel { meta.append("来自 \(src)") }
        if !meta.isEmpty { s += " — " + meta.joined(separator: "；") }
        return s
    }

    static func listing(_ items: [TodoItem], grouped: Bool = true) -> String {
        let today = Day.today
        var out = "今天是 \(today) \(Day.weekdayName(today))\n"
        for scope in TodoScope.allCases {
            let group = items.filter { $0.scope == scope }
            if grouped && group.isEmpty { continue }
            let open = group.filter { !$0.done }.count
            out += "\n## \(scope.title)（\(open) 项未完成 / 共 \(group.count) 项）\n"
            out += group.map { line($0, today: today) }.joined(separator: "\n")
            out += "\n"
        }
        if items.isEmpty { out += "\n（清单是空的）\n" }
        return out
    }
}

extension String {
    var nilIfBlank: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
