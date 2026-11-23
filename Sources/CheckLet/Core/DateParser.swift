import Foundation

/// 从一句话里识别日期 / 时间，比如：
///   "周三下午3点和客户开会"   → 本周三 15:00，标题「和客户开会」
///   "7月29是我女朋友的生日"   → 7 月 29 日，每年重复，标题「我女朋友的生日」
///   "下周交方案" / "15号交房租" / "3天后取快递" / "明晚8点看电影"
struct ParsedSchedule: Equatable {
    /// 具体哪天（yyyy-MM-dd）
    var day: String?
    /// 只说了"这周 / 下周"，没说哪天：那一周的周一
    var weekOf: String?
    /// "HH:mm"
    var time: String?
    /// 生日、纪念日这类每年都有的日子
    var yearly = false
    /// 考试、面试、截止日、生日这类"重要日期"
    var important = false
    /// 去掉日期、时间之后的标题
    var title: String
    /// 识别到的原文片段（界面上提示用）
    var matched: [String] = []

    var hasDate: Bool { day != nil || weekOf != nil }
    var isEmpty: Bool { day == nil && weekOf == nil && time == nil }
}

enum DateParser {
    private static let num = "(\\d{1,2}|[一二两三四五六七八九十]{1,3})"
    private static let period = "(凌晨|早上|早晨|上午|中午|午后|下午|傍晚|晚上|夜里|夜间)"

    private static let yearlyWords = ["生日", "纪念日", "周年", "忌日"]
    private static let importantWords = yearlyWords + [
        "考试", "面试", "截止", "ddl", "deadline", "婚礼", "答辩", "演唱会", "音乐节",
        "到期", "开学", "航班", "登机", "签证", "手术", "高考", "考研", "四六级",
    ]

    static func parse(_ text: String, today: String = Day.today) -> ParsedSchedule {
        var working = text
        var result = ParsedSchedule(title: text)
        let lower = text.lowercased()
        result.yearly = yearlyWords.contains { lower.contains($0) }
        result.important = importantWords.contains { lower.contains($0) }

        var periodHint: String?   // "今晚" "明早" 这类日期词里自带的时段

        // ---- 日期：按从具体到模糊的顺序，只取第一个匹配 ----
        typealias Rule = (pattern: String, resolve: ([String?]) -> (day: String?, weekOf: String?, period: String?)?)
        let rules: [Rule] = [
            // 2026年7月29日 / 2026-07-29 / 2026/7/29
            ("(\\d{4})\\s*[年\\-/.]\\s*(\\d{1,2})\\s*[月\\-/.]\\s*(\\d{1,2})\\s*[日号]?", { g in
                guard let y = int(g[1]), let m = int(g[2]), let d = int(g[3]),
                      let s = make(y, m, d) else { return nil }
                return (s, nil, nil)
            }),
            // 7月29日 / 七月二十九号 / 7月29
            ("\(num)\\s*月\\s*\(num)\\s*[日号]?", { g in
                guard let m = cn(g[1]), let d = cn(g[2]) else { return nil }
                return nextMonthDay(m, d, today: today).map { ($0, nil, nil) }
            }),
            // 7/29、07-29
            ("(?<![\\d/\\-.])(\\d{1,2}/\\d{1,2}|\\d{2}-\\d{2})(?![\\d/\\-.]|\\s*(?:个|天|次|人|岁|小时|分钟))", { g in
                let parts = (g[1] ?? "").split(whereSeparator: { $0 == "/" || $0 == "-" }).compactMap { Int($0) }
                guard parts.count == 2 else { return nil }
                return nextMonthDay(parts[0], parts[1], today: today).map { ($0, nil, nil) }
            }),
            // 下周三 / 这周五 / 星期天 / 礼拜一（"每周一"、"一周一次" 不算）
            ("(?<![每一两三几])(下下|下个?|这个?|本)?(?:周|星期|礼拜)([一二三四五六日天七1-7])(?![次遍回个])", { g in
                guard let wd = weekday(g[2]) else { return nil }
                let ws = Day.weekStart(of: today)
                var weeks = 0
                switch g[1] ?? "" {
                case "下下": weeks = 2
                case "下", "下个": weeks = 1
                case "": // 没说哪周：已经过去的那天指下周
                    if Day.adding(days: wd, to: ws) < today { weeks = 1 }
                default: weeks = 0
                }
                return (Day.adding(days: weeks * 7 + wd, to: ws), nil, nil)
            }),
            // 周末 / 下周末
            ("(下下|下个?|这个?|本)?(?:周末)", { g in
                let ws = Day.weekStart(of: today)
                let weeks = g[1] == "下下" ? 2 : ((g[1] ?? "").hasPrefix("下") ? 1 : 0)
                var d = Day.adding(days: weeks * 7 + 5, to: ws)
                if weeks == 0 && d < today { d = today } // 周日说"周末"就是今天
                return (d, nil, nil)
            }),
            // 下个月 / 本月 + 15号；单独的 15号
            ("(?:(下个?月|这个?月|本月)|(?<![\\d月]))(\\d{1,2}|[一二三四五六七八九十]{1,3})\\s*号", { g in
                guard let d = cn(g[2]), (1...31).contains(d) else { return nil }
                return dayOfMonth(d, nextMonth: (g[1] ?? "").hasPrefix("下"), explicit: g[1] != nil, today: today)
                    .map { ($0, nil, nil) }
            }),
            // 月底 / 下个月底
            ("(下个?)?月底", { g in
                guard let base = Day.date(today) else { return nil }
                let cal = Day.calendar
                let monthOffset = g[1] != nil ? 1 : 0
                guard let target = cal.date(byAdding: .month, value: monthOffset, to: base),
                      let range = cal.range(of: .day, in: .month, for: target) else { return nil }
                var c = cal.dateComponents([.year, .month], from: target)
                c.day = range.count
                return cal.date(from: c).map { (Day.string($0), nil, nil) }
            }),
            // 大后天 / 后天 / 明天 / 今天（含 今晚、明早 这类带时段的）
            ("(大后天|后天|明天|明日|明儿|明早|明晚|今天|今日|今儿|今早|今晚|今夜)", { g in
                let w = g[1] ?? ""
                let offset: Int
                switch w {
                case "大后天": offset = 3
                case "后天": offset = 2
                case let x where x.hasPrefix("明"): offset = 1
                default: offset = 0
                }
                let p: String? = w.hasSuffix("早") ? "早上" : (w.hasSuffix("晚") || w.hasSuffix("夜") ? "晚上" : nil)
                return (Day.adding(days: offset, to: today), nil, p)
            }),
            // 3天后 / 过两天 / 一周后
            ("\(num)\\s*天(?:后|之后|以后)|过\\s*\(num)\\s*天", { g in
                guard let n = cn(g[1] ?? g[2]) else { return nil }
                return (Day.adding(days: n, to: today), nil, nil)
            }),
            ("\(num)\\s*(?:周|个星期|个礼拜)(?:后|之后|以后)", { g in
                guard let n = cn(g[1]) else { return nil }
                return (Day.adding(days: n * 7, to: today), nil, nil)
            }),
            // 只说了哪一周：这周 / 本周 / 下周 / 下下周
            ("(下下|下个?|这个?|本)(?:周|星期|礼拜)(?![一二三四五六日天七1-7末])", { g in
                let ws = Day.weekStart(of: today)
                let weeks = g[1] == "下下" ? 2 : ((g[1] ?? "").hasPrefix("下") ? 1 : 0)
                return (nil, Day.adding(days: weeks * 7, to: ws), nil)
            }),
        ]

        for rule in rules {
            guard let (range, groups) = firstMatch(rule.pattern, in: working),
                  let r = rule.resolve(groups) else { continue }
            result.day = r.day
            result.weekOf = r.weekOf
            periodHint = r.period
            result.matched.append(String(working[range]))
            working.replaceSubrange(range, with: " ")
            break
        }

        // ---- 时间 ----
        let timeRules: [(String, Bool)] = [
            ("\(period)?\\s*(\\d{1,2})[:：](\\d{2})", true),
            ("\(period)?\\s*\(num)\\s*点\\s*(半|整|一刻|三刻|\(num)\\s*分?)?", false),
        ]
        for (pattern, colon) in timeRules {
            guard let (range, g) = firstMatch(pattern, in: working), var h = cn(g[2]) else { continue }
            let p = g[1] ?? periodHint
            var m = 0
            if colon {
                m = Int(g[3] ?? "") ?? 0
            } else {
                switch g[3] {
                case "半": m = 30
                case "一刻": m = 15
                case "三刻": m = 45
                case nil, "整": m = 0
                default: m = cn(g[4]) ?? 0
                }
                // "3点建议" 这种不是时间：要么有时段词，要么句子里有日期，要么有 "半 / 分"
                guard g[1] != nil || periodHint != nil || result.hasDate || g[3] != nil else { continue }
            }
            guard (0...24).contains(h), (0...59).contains(m) else { continue }
            switch p {
            case "下午", "午后", "傍晚", "晚上", "夜里", "夜间": if h < 12 { h += 12 }
            case "中午": if h < 11 { h += 12 }
            case "凌晨": if h == 12 { h = 0 }
            case nil: if (1...6).contains(h) { h += 12 } // "3点开会" 多半是下午
            default: break
            }
            if h == 24 { h = 23; m = 59 }
            result.time = String(format: "%02d:%02d", h, m)
            result.matched.append(String(working[range]).trimmingCharacters(in: .whitespaces))
            working.replaceSubrange(range, with: " ")
            if result.day == nil && result.weekOf == nil { result.day = today }
            break
        }

        if !result.isEmpty {
            let cleaned = clean(working)
            result.title = cleaned.isEmpty ? text.trimmingCharacters(in: .whitespacesAndNewlines) : cleaned
        }
        return result
    }

    // MARK: - 工具

    private static func clean(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        // 去掉开头的连接词：「是我女朋友的生日」「要交报告」「提醒我去医院」
        t = t.replacingOccurrences(of: "^(?:[\\s,，、:：;；。~～-]|的|是|要|得|提醒我|提醒|记得)+",
                                   with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "[\\s,，、:：;；~～-]+$", with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: " ([的了])", with: "$1", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstMatch(_ pattern: String, in s: String) -> (Range<String.Index>, [String?])? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let r = Range(m.range, in: s) else { return nil }
        let groups: [String?] = (0..<m.numberOfRanges).map { i in
            Range(m.range(at: i), in: s).map { String(s[$0]) }
        }
        return (r, groups)
    }

    private static func int(_ s: String?) -> Int? { s.flatMap { Int($0) } }

    /// 阿拉伯数字或中文数字（一 ~ 三十一）
    static func cn(_ s: String?) -> Int? {
        guard let s = s?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        if let n = Int(s) { return n }
        let digits: [Character: Int] = ["零": 0, "〇": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4,
                                        "五": 5, "六": 6, "七": 7, "八": 8, "九": 9]
        let chars = Array(s)
        if let i = chars.firstIndex(of: "十") {
            let tens = i == 0 ? 1 : (chars.count > 0 ? digits[chars[0]] : nil)
            let ones = i + 1 < chars.count ? digits[chars[i + 1]] : 0
            guard let t = tens, let o = ones, i <= 1, chars.count <= i + 2 else { return nil }
            return t * 10 + o
        }
        guard chars.count == 1 else { return nil }
        return digits[chars[0]]
    }

    private static func weekday(_ s: String?) -> Int? {
        switch s {
        case "一", "1": return 0
        case "二", "2": return 1
        case "三", "3": return 2
        case "四", "4": return 3
        case "五", "5": return 4
        case "六", "6": return 5
        case "日", "天", "七", "7": return 6
        default: return nil
        }
    }

    private static func make(_ y: Int, _ m: Int, _ d: Int) -> String? {
        guard (1...12).contains(m), (1...31).contains(d) else { return nil }
        let comps = DateComponents(year: y, month: m, day: d)
        guard comps.isValidDate(in: Day.calendar), let date = Day.calendar.date(from: comps) else { return nil }
        return Day.string(date)
    }

    /// 某月某日：今年还没过就是今年，否则明年
    static func nextMonthDay(_ m: Int, _ d: Int, today: String) -> String? {
        guard let t = Day.date(today) else { return nil }
        let y = Day.calendar.component(.year, from: t)
        for year in [y, y + 1, y + 2, y + 3, y + 4] { // 2 月 29 日最多要等 4 年
            if let s = make(year, m, d), s >= today { return s }
        }
        return nil
    }

    private static func dayOfMonth(_ d: Int, nextMonth: Bool, explicit: Bool, today: String) -> String? {
        guard let t = Day.date(today) else { return nil }
        let cal = Day.calendar
        var c = cal.dateComponents([.year, .month], from: t)
        if nextMonth { c.month = (c.month ?? 1) + 1 }
        for _ in 0..<3 {
            guard let first = cal.date(from: c) else { return nil }
            let fc = cal.dateComponents([.year, .month], from: first)
            if let s = make(fc.year ?? 0, fc.month ?? 0, d), explicit || s >= today { return s }
            c.month = (c.month ?? 1) + 1
        }
        return nil
    }
}
