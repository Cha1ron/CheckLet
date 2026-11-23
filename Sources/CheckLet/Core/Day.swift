import Foundation

/// 日期工具：所有"天"都用本地时区的 "yyyy-MM-dd" 字符串表示，便于存储和比较（字符串顺序 == 时间顺序）。
enum Day {
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2 // 周一为一周的开始
        c.timeZone = .current
        return c
    }()

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func string(_ date: Date) -> String { formatter.string(from: date) }
    static func date(_ s: String) -> Date? { formatter.date(from: s) }
    static func isValid(_ s: String) -> Bool { date(s) != nil }

    static var today: String { string(Date()) }

    static func adding(days: Int, to s: String) -> String {
        guard let d = date(s), let r = calendar.date(byAdding: .day, value: days, to: d) else { return s }
        return string(r)
    }

    /// 某天所在周的周一
    static func weekStart(of s: String) -> String {
        guard let d = date(s) else { return s }
        let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: d)
        guard let monday = calendar.date(from: comps) else { return s }
        return string(monday)
    }

    static var thisWeekStart: String { weekStart(of: today) }

    /// 两个日期之间相差的天数（b - a）
    static func daysBetween(_ a: String, _ b: String) -> Int {
        guard let da = date(a), let db = date(b) else { return 0 }
        return calendar.dateComponents([.day], from: da, to: db).day ?? 0
    }

    static func isSameDay(_ d: Date, _ s: String) -> Bool { string(d) == s }

    private static let weekdayNames = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]

    static func weekdayName(_ s: String) -> String {
        guard let d = date(s) else { return "" }
        return weekdayNames[calendar.component(.weekday, from: d) - 1]
    }

    /// "11月23日"
    static func shortCN(_ s: String) -> String {
        guard let d = date(s) else { return s }
        let c = calendar.dateComponents([.month, .day], from: d)
        return "\(c.month ?? 0)月\(c.day ?? 0)日"
    }

    /// 解析自然一点的日期输入：today/tomorrow/今天/明天/后天/+3/2026-12-01/12-01
    static func parse(_ raw: String?) -> String? {
        guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        s = s.lowercased()
        switch s {
        case "today", "今天", "今日": return today
        case "tomorrow", "明天", "明日": return adding(days: 1, to: today)
        case "后天": return adding(days: 2, to: today)
        case "yesterday", "昨天": return adding(days: -1, to: today)
        default: break
        }
        if s.hasPrefix("+"), let n = Int(s.dropFirst()) { return adding(days: n, to: today) }
        if isValid(s) { return string(date(s)!) }
        // "12-01" / "12/1" → 今年（如果已过则明年）
        let parts = s.split(whereSeparator: { $0 == "-" || $0 == "/" || $0 == "." }).compactMap { Int($0) }
        if parts.count == 2 {
            let year = calendar.component(.year, from: Date())
            for y in [year, year + 1] {
                if let d = calendar.date(from: DateComponents(year: y, month: parts[0], day: parts[1])) {
                    let str = string(d)
                    if str >= today { return str }
                }
            }
        }
        if parts.count == 3, let d = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) {
            return string(d)
        }
        return nil
    }
}
