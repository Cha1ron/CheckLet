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
    let store: TodoStore
    let classifier: Classifier

    init(store: TodoStore = .shared) {
        self.store = store
        self.classifier = Classifier(store: store)
    }

    // MARK: 查询

    func list(scope: TodoScope?, category: TodoCategory? = nil,
              includeDone: Bool = true, includeUpcoming: Bool = false) -> [TodoItem] {
        let all = store.load()
        let today = Day.today
        let scopes = scope.map { [$0] } ?? TodoScope.allCases
        var result: [TodoItem] = []
        var seen = Set<String>()
        for s in scopes {
            var items = all.visible(s, today: today)
            if includeUpcoming {
                let upcoming = all.filter { $0.scope == s && !$0.done && !$0.isVisible(today: today) }
                    .sorted { $0.day < $1.day }
                items += upcoming
            }
            if !includeDone { items = items.filter { !$0.done } }
            if let category { items = items.filter { $0.displayCategory == category } }
            items = items.filter { seen.insert($0.id).inserted }
            result += items
        }
        return result
    }

    // MARK: 修改

    /// 添加待办。
    /// - scope: 明确指定的清单；nil = 根据识别到的日期自动决定（没日期就用 preferredScope）
    /// - date: 明确给的日期（优先）；没有就从标题里识别「周三」「7月29日」这类说法
    /// - fallbackDate: 标题里也没识别到日期时用（比如面板里重要日期的日期选择器）
    @discardableResult
    func add(title rawTitle: String, scope explicitScope: TodoScope? = nil, preferredScope: TodoScope = .today,
             date: String? = nil, fallbackDate: String? = nil, time explicitTime: String? = nil,
             yearly explicitYearly: Bool? = nil, parseDates: Bool = true,
             note: String? = nil, source: String? = nil,
             category explicit: TodoCategory? = nil, categorySource: CategorySource = .user) throws -> TodoItem {
        // 支持在内容里写 "#生活" 指定分类
        let (tagStripped, tagged) = TodoCategory.extractTag(from: rawTitle)
        var title = tagStripped.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw TodoError.invalid("待办内容不能为空") }

        let today = Day.today
        var due = try parseDate(date)
        var weekOf: String?
        var time = try parseTime(explicitTime)
        let parsed = DateParser.parse(title, today: today)
        if parseDates {
            if due == nil && time == nil && !parsed.isEmpty {
                // 标题里说了日期 / 时间：用它，并把这几个字从标题里去掉
                due = parsed.day
                weekOf = parsed.weekOf
                time = parsed.time
                title = parsed.title
            } else if due == nil, explicitScope == .date || preferredScope == .date, let d = parsed.day {
                due = d
            }
        }
        if due == nil, weekOf == nil, let f = try parseDate(fallbackDate) { due = f }

        let scope: TodoScope
        if let explicitScope {
            scope = explicitScope
        } else if due != nil || weekOf != nil {
            scope = preferredScope == .date && due != nil
                ? .date
                : Self.autoScope(due: due, weekOf: weekOf, important: parsed.important, today: today)
        } else {
            scope = preferredScope
        }

        var yearly = explicitYearly ?? (scope == .date && parsed.yearly)
        let day: String
        switch scope {
        case .today: day = due ?? today
        case .week: day = Day.weekStart(of: due ?? weekOf ?? today)
        case .date:
            guard var d = due else { throw TodoError.invalid("重要日期需要提供 date（格式 YYYY-MM-DD）") }
            if yearly, d < today { d = Self.nextOccurrence(of: d, onOrAfter: today) ?? d }
            due = d
            day = d
        }
        if scope != .date { yearly = false }

        let category: TodoCategory
        let how: CategorySource
        if let chosen = explicit ?? tagged {
            category = chosen
            how = explicit != nil ? categorySource : .user
            if how == .user { classifier.learn(title: title, category: chosen) }
        } else {
            (category, how) = classifier.classify(title)
        }

        return try store.mutate { items in
            let ids = Set(items.map(\.id))
            var id = Self.newID()
            while ids.contains(id) { id = Self.newID() }
            var item = TodoItem(id: id, title: title, scope: scope, day: day,
                                note: note?.nilIfBlank, source: source?.nilIfBlank)
            item.category = category
            item.categorySource = how
            item.due = due
            item.time = time
            item.yearly = yearly ? true : nil
            items.append(item)
            return item
        }
    }

    /// 根据日期决定放进哪个清单
    ///  - 生日 / 考试 / 截止日这类 → 重要日期
    ///  - 今天（或已经过了的日子）→ 今日
    ///  - 这周、下周 → 本周（到那天会自动出现在今日）
    ///  - 更远的 → 重要日期（带倒计时）
    static func autoScope(due: String?, weekOf: String?, important: Bool, today: String = Day.today) -> TodoScope {
        guard let due else { return .week }
        if important { return .date }
        if due <= today { return .today }
        let ws = Day.weekStart(of: today)
        let target = Day.weekStart(of: due)
        if target == ws || target == Day.adding(days: 7, to: ws) { return .week }
        return .date
    }

    /// 每年重复的日子：下一次是哪天
    static func nextOccurrence(of day: String, onOrAfter today: String) -> String? {
        guard let d = Day.date(day) else { return nil }
        let c = Day.calendar.dateComponents([.month, .day], from: d)
        return DateParser.nextMonthDay(c.month ?? 1, c.day ?? 1, today: today)
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
                date: String? = nil, time: String? = nil, yearly: Bool? = nil, note: String? = nil,
                category: TodoCategory? = nil, categorySource: CategorySource = .user) throws -> TodoItem {
        let parsed = try parseDate(date)
        let clearTime = time.map { $0.trimmingCharacters(in: .whitespaces).isEmpty || $0 == "none" } ?? false
        let parsedTime = clearTime ? nil : try parseTime(time)
        let updated: TodoItem = try store.mutate { items in
            let i = try Self.resolve(ref, in: items)
            if let t = title?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
                items[i].title = t
                // 改了标题、而分类是自动猜的 → 重新猜
                if category == nil, items[i].categorySource?.isAuto ?? true {
                    let (c, how) = classifier.classify(t)
                    items[i].category = c
                    items[i].categorySource = how
                }
            }
            if let category {
                items[i].category = category
                items[i].categorySource = categorySource
            }
            if let note { items[i].note = note.nilIfBlank }
            if clearTime { items[i].time = nil } else if let parsedTime { items[i].time = parsedTime }
            let newScope = scope ?? items[i].scope
            if let parsed { items[i].due = parsed } else if scope != nil, scope != items[i].scope {
                // 换清单但没给日期：移到今日 / 本周就不再绑定原来那天
                if newScope != .date { items[i].due = nil }
            }
            if scope != nil || parsed != nil {
                switch newScope {
                case .today: items[i].day = parsed ?? (scope != nil ? Day.today : items[i].day)
                case .week: items[i].day = Day.weekStart(of: parsed ?? (scope != nil ? Day.today : items[i].day))
                case .date:
                    guard let d = parsed ?? (items[i].scope == .date ? items[i].day : nil) else {
                        throw TodoError.invalid("移到「重要日期」需要提供 date（YYYY-MM-DD）")
                    }
                    items[i].day = d
                    items[i].due = d
                }
                items[i].scope = newScope
            }
            if let yearly { items[i].yearly = yearly && items[i].scope == .date ? true : nil }
            if items[i].scope != .date { items[i].yearly = nil }
            return items[i]
        }
        if category != nil, categorySource == .user {
            classifier.learn(title: updated.title, category: updated.displayCategory)
        }
        return updated
    }

    /// 推迟一天（有具体日期的连日期一起推）
    @discardableResult
    func postpone(_ ref: String, days: Int = 1) throws -> TodoItem {
        try store.mutate { items in
            let i = try Self.resolve(ref, in: items)
            let base = max(items[i].eventDay ?? items[i].day, Day.today)
            let target = Day.adding(days: days, to: base)
            switch items[i].scope {
            case .today: items[i].day = target
            case .week: items[i].day = Day.weekStart(of: target)
            case .date: items[i].day = target
            }
            if items[i].due != nil || items[i].scope == .date { items[i].due = target }
            return items[i]
        }
    }

    /// 每天跑一次：每年重复的日子过了之后，挪到明年并取消打勾
    @discardableResult
    func rollYearly(today: String = Day.today) throws -> Int {
        let all = store.load()
        guard all.contains(where: { $0.isYearly && $0.day < today }) else { return 0 }
        return try store.mutate { items in
            var n = 0
            for i in items.indices where items[i].isYearly && items[i].day < today {
                guard let next = Self.nextOccurrence(of: items[i].day, onOrAfter: today) else { continue }
                items[i].day = next
                items[i].due = next
                items[i].done = false
                items[i].doneAt = nil
                n += 1
            }
            return n
        }
    }

    /// 给没有分类的旧待办补上分类（升级后第一次启动时）
    @discardableResult
    func classifyUncategorized() throws -> Int {
        try store.mutate { items in
            var n = 0
            for i in items.indices where items[i].category == nil {
                let (c, how) = classifier.classify(items[i].title)
                items[i].category = c
                items[i].categorySource = how
                n += 1
            }
            return n
        }
    }

    /// Apple Intelligence 给出的分类：只覆盖仍然是"自动猜测"的条目
    func applyModelCategory(id: String, title: String, category: TodoCategory) throws {
        try store.mutate { items in
            guard let i = items.firstIndex(where: { $0.id == id }), items[i].title == title,
                  items[i].categorySource == .rule else { return }
            items[i].category = category
            items[i].categorySource = .model
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
            items.removeAll { $0.done && !$0.isYearly && !$0.isVisible() }
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

    /// "15:30" / "3点半" / "下午3点" → "HH:mm"
    private func parseTime(_ raw: String?) throws -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespaces), !raw.isEmpty, raw != "none" else { return nil }
        let parts = raw.split(whereSeparator: { $0 == ":" || $0 == "：" }).compactMap { Int($0) }
        if parts.count == 2, (0...23).contains(parts[0]), (0...59).contains(parts[1]) {
            return String(format: "%02d:%02d", parts[0], parts[1])
        }
        if let t = DateParser.parse(raw).time { return t }
        throw TodoError.invalid("无法识别时间「\(raw)」，请使用 HH:mm 格式，如 15:30")
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
        var s = "\(t.done ? "[x]" : "[ ]") (\(t.id)) [\(t.displayCategory.label)] \(t.title)"
        var meta: [String] = []
        switch t.scope {
        case .today:
            if t.day > today { meta.append("\(t.day) \(Day.weekdayName(t.day))") }
            else if t.isCarriedOver(today: today) { meta.append("从 \(t.day) 顺延") }
        case .week:
            if let d = t.due { meta.append("\(d) \(Day.weekdayName(d))\(t.time.map { " " + $0 } ?? "")") }
            else if t.day > Day.weekStart(of: today) { meta.append("\(t.day) 那周") }
            if t.isCarriedOver(today: today) { meta.append(t.due != nil ? "已过期" : "上周遗留") }
        case .date:
            meta.append("\(t.day) \(Day.weekdayName(t.day))\(t.time.map { " " + $0 } ?? "")，\(t.countdownText(today: today))")
            if t.isYearly { meta.append("每年") }
        }
        if t.scope == .today, let time = t.time { meta.append(time) }
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
