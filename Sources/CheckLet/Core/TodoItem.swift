import Foundation

/// 三个清单：今日 / 本周 / 重要日期
enum TodoScope: String, Codable, CaseIterable, Identifiable {
    case today
    case week
    case date

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "今日"
        case .week: return "本周"
        case .date: return "重要日期"
        }
    }

    /// 允许 AI / 命令行用多种叫法
    init?(loose: String?) {
        guard let s = loose?.trimmingCharacters(in: .whitespaces).lowercased(), !s.isEmpty else { return nil }
        switch s {
        case "today", "day", "daily", "今日", "今天": self = .today
        case "week", "weekly", "本周", "周", "这周": self = .week
        case "date", "dates", "important", "important_date", "important_dates", "event", "重要日期", "日期": self = .date
        default: return nil
        }
    }
}

struct TodoItem: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var scope: TodoScope
    /// today: 这条待办属于哪天；week: 所属周的周一；date: 重要日期当天
    var day: String
    var done: Bool = false
    var note: String?
    /// 来源：nil 表示手动添加，否则是 AI 工具名，如 "Claude" / "Codex"
    var source: String?
    var createdAt: Date = Date()
    var doneAt: Date?
    /// 分类 id 与来源（存成字符串，未来新增分类时旧版本也不会读坏文件）
    var categoryID: String?
    var categorySourceID: String?
    /// 具体哪天要做 / 发生（用户说了日期才有）。本周待办的 day 是周一，due 才是具体哪天
    var due: String?
    /// 具体时间 "HH:mm"
    var time: String?
    /// 每年重复（生日、纪念日）
    var yearly: Bool?

    var isYearly: Bool { yearly ?? false }

    /// 有明确日期的条目：会同步到日历，到了那天会出现在「今日」
    var eventDay: String? { due ?? (scope == .date ? day : nil) }

    var category: TodoCategory? {
        get { categoryID.flatMap(TodoCategory.init(rawValue:)) }
        set { categoryID = newValue?.rawValue }
    }

    var categorySource: CategorySource? {
        get { categorySourceID.flatMap(CategorySource.init(rawValue:)) }
        set { categorySourceID = newValue?.rawValue }
    }

    var displayCategory: TodoCategory { category ?? .other }

    // MARK: - 显示规则

    /// 当前是否应出现在清单里
    func isVisible(today: String = Day.today) -> Bool {
        switch scope {
        case .today:
            guard day <= today else { return false } // 未来某天的待办，到那天再出现
            if !done { return true }                  // 未完成的会一直顺延
            return doneAt.map { Day.isSameDay($0, today) } ?? false
        case .week:
            let ws = Day.weekStart(of: today)
            guard day <= ws else { return false }
            if !done { return true }
            return doneAt.map { Day.string($0) >= ws } ?? false
        case .date:
            if !done { return true }
            return doneAt.map { Day.isSameDay($0, today) } ?? false
        }
    }

    /// 本周 / 重要日期里、到了日子的条目，也显示在「今日」
    func showsInToday(today: String = Day.today) -> Bool {
        guard scope != .today, let d = eventDay, isVisible(today: today) else { return false }
        if done { return d <= today }
        switch scope {
        case .week: return d <= today        // 没做完的继续留在今日
        default: return d == today
        }
    }

    /// 今日待办是从之前的日子顺延来的
    func isCarriedOver(today: String = Day.today) -> Bool {
        if scope == .week, let d = due, !done, d < today { return true }
        switch scope {
        case .today: return !done && day < today
        case .week: return !done && day < Day.weekStart(of: today)
        case .date: return false
        }
    }

    /// 重要日期倒计时文案
    func countdownText(today: String = Day.today) -> String {
        let n = Day.daysBetween(today, day)
        switch n {
        case 0: return "就是今天"
        case 1: return "明天"
        case 2: return "后天"
        case let x where x > 0: return "还有 \(x) 天"
        default: return "已过 \(-n) 天"
        }
    }

    var sourceLabel: String? {
        guard let s = source?.lowercased(), !s.isEmpty else { return nil }
        if s.contains("claude") { return "Claude" }
        if s.contains("codex") || s.contains("openai") { return "Codex" }
        if s.contains("muse") { return "Muse" }
        if s.contains("cursor") { return "Cursor" }
        if s == "cli" { return "CLI" }
        return String(source!.prefix(12))
    }
}

struct TodoFile: Codable {
    var version: Int = 1
    var items: [TodoItem] = []
}

extension Array where Element == TodoItem {
    /// 某个清单下应显示的条目（已排序）。「今日」还会带上本周 / 重要日期里到了日子的条目
    func visible(_ scope: TodoScope, today: String = Day.today) -> [TodoItem] {
        let list = filter {
            ($0.scope == scope && $0.isVisible(today: today)) || (scope == .today && $0.showsInToday(today: today))
        }
        return list.sorted { a, b in
            if a.done != b.done { return !a.done }
            let da = a.eventDay ?? (scope == .date ? a.day : "9999"), db = b.eventDay ?? (scope == .date ? b.day : "9999")
            if da != db { return da < db }
            let ta = a.time ?? "99", tb = b.time ?? "99"
            if ta != tb { return ta < tb }
            return a.createdAt < b.createdAt
        }
    }

    /// 本周清单下方预告：下周已经安排好的事
    func nextWeek(today: String = Day.today) -> [TodoItem] {
        let next = Day.adding(days: 7, to: Day.weekStart(of: today))
        return filter { $0.scope == .week && !$0.done && $0.day == next }
            .sorted { ($0.due ?? "9999", $0.time ?? "99") < ($1.due ?? "9999", $1.time ?? "99") }
    }
}
