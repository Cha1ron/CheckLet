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

    /// 今日待办是从之前的日子顺延来的
    func isCarriedOver(today: String = Day.today) -> Bool {
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
    /// 某个清单下应显示的条目（已排序）
    func visible(_ scope: TodoScope, today: String = Day.today) -> [TodoItem] {
        let list = filter { $0.scope == scope && $0.isVisible(today: today) }
        return list.sorted { a, b in
            if a.done != b.done { return !a.done }
            if scope == .date, a.day != b.day { return a.day < b.day }
            return a.createdAt < b.createdAt
        }
    }
}
