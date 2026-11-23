import Foundation

/// 待办分类
enum TodoCategory: String, Codable, CaseIterable, Identifiable {
    case work, study, life, health, finance, social, other

    var id: String { rawValue }

    var name: String {
        switch self {
        case .work: return "工作"
        case .study: return "学习"
        case .life: return "生活"
        case .health: return "健康"
        case .finance: return "财务"
        case .social: return "人情"
        case .other: return "其他"
        }
    }

    var emoji: String {
        switch self {
        case .work: return "💼"
        case .study: return "📚"
        case .life: return "🏠"
        case .health: return "💪"
        case .finance: return "💰"
        case .social: return "💝"
        case .other: return "📌"
        }
    }

    /// 给 AI 看的含义说明
    var meaning: String {
        switch self {
        case .work: return "工作/职场/项目/会议/客户"
        case .study: return "学习/课程/考试/阅读/技能提升"
        case .life: return "日常生活/家务/宠物/购物/快递/出行杂事"
        case .health: return "健康/运动/健身/医疗/作息"
        case .finance: return "钱相关/账单/房租/还款/报销/理财"
        case .social: return "家人朋友/人际/生日纪念日/聚会/礼物"
        case .other: return "以上都不合适"
        }
    }

    var label: String { "\(emoji) \(name)" }

    /// 颜色（十六进制），UI 用
    var hex: UInt32 {
        switch self {
        case .work: return 0x5B8DEF
        case .study: return 0x9B7BEA
        case .life: return 0xF2994A
        case .health: return 0x34C38F
        case .finance: return 0xC9971C
        case .social: return 0xF06A9B
        case .other: return 0x9AA0A6
        }
    }

    /// 接受 id、中文名、emoji 和一些同义词
    init?(loose raw: String?) {
        guard let s = raw?.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: "#", with: ""),
              !s.isEmpty else { return nil }
        if let c = TodoCategory(rawValue: s) { self = c; return }
        if let c = TodoCategory.allCases.first(where: { $0.name == s || $0.emoji == s || $0.label == s }) { self = c; return }
        let synonyms: [String: TodoCategory] = [
            "职场": .work, "上班": .work, "job": .work, "office": .work,
            "学业": .study, "learn": .study, "learning": .study, "school": .study,
            "日常": .life, "日常生活": .life, "家务": .life, "宠物": .life, "购物": .life, "家": .life, "home": .life, "chores": .life,
            "运动": .health, "身体": .health, "医疗": .health, "fitness": .health, "sport": .health,
            "钱": .finance, "账单": .finance, "理财": .finance, "money": .finance, "bills": .finance,
            "社交": .social, "家人": .social, "朋友": .social, "人际": .social, "family": .social, "friends": .social,
            "杂事": .other, "misc": .other,
        ]
        if let c = synonyms[s] { self = c; return }
        return nil
    }

    /// 从输入文字里提取 "#生活" 这样的标签，返回去掉标签后的文字
    static func extractTag(from text: String) -> (String, TodoCategory?) {
        let pattern = "[#＃]([\\p{L}\\p{N}_]+)"
        guard let re = try? NSRegularExpression(pattern: pattern) else { return (text, nil) }
        let ns = text as NSString
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            if let c = TodoCategory(loose: ns.substring(with: m.range(at: 1))) {
                let stripped = ns.replacingCharacters(in: m.range, with: "")
                    .replacingOccurrences(of: "  ", with: " ")
                    .trimmingCharacters(in: .whitespaces)
                return (stripped, c)
            }
        }
        return (text, nil)
    }
}

/// 分类是怎么来的
enum CategorySource: String, Codable {
    case user      // 用户手动选的
    case ai        // Claude / Codex 等通过 MCP 指定
    case learned   // 根据用户以前的修正推断
    case rule      // 关键词规则
    case model     // Apple Intelligence 端侧模型

    var isAuto: Bool { self == .learned || self == .rule || self == .model }
}
