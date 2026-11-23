import Foundation

/// 本地自动分类：关键词规则 + 从用户修正中学习。离线、即时、所有 Mac 都能用。
/// （有 Apple Intelligence 的 Mac 上，App 还会再用端侧模型复核一遍，见 SmartClassifier。）
final class Classifier {
    private let fileURL: URL
    private var memory = Memory()

    struct Memory: Codable {
        /// 用户修正过的完整标题 → 分类
        var titles: [String: TodoCategory] = [:]
        /// 从修正中学到的词 → 分类
        var terms: [String: TodoCategory] = [:]
    }

    init(store: TodoStore = .shared) {
        fileURL = store.directory.appendingPathComponent("learned-categories.json")
        reloadMemory()
    }

    func reloadMemory() {
        if let data = try? Data(contentsOf: fileURL),
           let m = try? JSONDecoder().decode(Memory.self, from: data) {
            memory = m
        }
    }

    // MARK: 分类

    func classify(_ rawTitle: String) -> (category: TodoCategory, source: CategorySource) {
        let title = Self.normalize(rawTitle)
        if let c = memory.titles[title] { return (c, .learned) }

        var scores: [TodoCategory: Double] = [:]
        var learnedHit = false
        for (term, c) in memory.terms where title.contains(term) {
            scores[c, default: 0] += 2.5 + Double(term.count) * 0.5
            learnedHit = true
        }
        for (c, words) in Self.keywords {
            for w in words where title.contains(w) {
                scores[c, default: 0] += Double(min(w.count, 4))
            }
        }
        guard let best = scores.max(by: { a, b in
            a.value != b.value ? a.value < b.value : Self.priority(a.key) > Self.priority(b.key)
        }), best.value > 0 else {
            return (.other, .rule)
        }
        return (best.key, learnedHit ? .learned : .rule)
    }

    // MARK: 学习

    /// 用户把某条待办改成了某个分类 → 记住
    func learn(title rawTitle: String, category: TodoCategory) {
        reloadMemory()
        let title = Self.normalize(rawTitle)
        guard !title.isEmpty else { return }
        memory.titles[title] = category
        // 记住这句话里"有区分度"的词：不在停用词表、也不是其他分类的内置关键词
        for term in Self.terms(of: title) {
            let builtin = Self.keywords.first { $0.value.contains(term) }?.key
            if builtin == category { continue }
            memory.terms[term] = category
        }
        // 控制大小
        if memory.titles.count > 500 { memory.titles = Dictionary(uniqueKeysWithValues: memory.titles.suffix(400).map { ($0.key, $0.value) }) }
        if memory.terms.count > 2000 { memory.terms = Dictionary(uniqueKeysWithValues: memory.terms.suffix(1500).map { ($0.key, $0.value) }) }
        if let data = try? JSONEncoder().encode(memory) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// 给 Apple Intelligence 当参考的用户习惯样例
    func examples(limit: Int = 12) -> [(String, TodoCategory)] {
        Array(memory.titles.prefix(limit)).map { ($0.key, $0.value) }
    }

    // MARK: 工具

    static func normalize(_ s: String) -> String {
        s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 中文取相邻两字，英文取单词
    static func terms(of s: String) -> Set<String> {
        var out = Set<String>()
        var han: [Character] = []
        var word = ""
        func flushHan() {
            if han.count >= 2 {
                for i in 0..<(han.count - 1) { out.insert(String(han[i...i + 1])) }
            }
            han.removeAll()
        }
        func flushWord() {
            if word.count >= 3 { out.insert(word) }
            word = ""
        }
        for ch in s {
            if ch.unicodeScalars.allSatisfy({ (0x4E00...0x9FFF).contains($0.value) }) {
                flushWord(); han.append(ch)
            } else if ch.isLetter {
                flushHan(); word.append(ch)
            } else {
                flushHan(); flushWord()
            }
        }
        flushHan(); flushWord()
        return out.subtracting(stopTerms)
    }

    private static let stopTerms: Set<String> = [
        "给我", "我家", "我的", "一下", "一个", "今天", "明天", "后天", "这周", "下周", "本周", "记得", "提醒",
        "要去", "需要", "准备", "完成", "处理", "安排", "继续", "开始", "看看", "然后", "还有", "and", "the", "for", "with",
    ]

    /// 同分时的优先级（越小越优先）
    private static func priority(_ c: TodoCategory) -> Int {
        [.social, .finance, .health, .study, .work, .life, .other].firstIndex(of: c) ?? 9
    }

    static let keywords: [TodoCategory: [String]] = [
        .work: [
            "工作", "上班", "会议", "开会", "周会", "例会", "晨会", "周报", "日报", "月报", "季报", "汇报", "述职", "报告",
            "需求", "项目", "上线", "发版", "发布", "迭代", "排期", "客户", "甲方", "老板", "领导", "同事", "团队",
            "面试", "简历", "招聘", "入职", "离职", "邮件", "合同", "方案", "ppt", "文档", "评审", "review", "bug",
            "代码", "部署", "提交", "pull request", "加班", "出差", "拜访", "对接", "okr", "kpi", "设计稿", "原型", "产品",
            "运营", "交付", "deadline", "ddl", "测试", "复盘", "立项", "预算表", "offer", "meeting", "jira", "slack",
            "飞书", "钉钉", "企业微信", "工单", "docs", "上架", "app store", "审核", "签约", "谈判", "演示", "demo",
        ],
        .study: [
            "学习", "复习", "预习", "作业", "考试", "期末", "期中", "背单词", "单词", "课程", "上课", "网课", "课件",
            "读书", "看书", "阅读", "论文", "笔记", "练习", "刷题", "英语", "日语", "雅思", "托福", "考研", "考公",
            "四六级", "培训", "教程", "文献", "讲座", "听课", "毕设", "答辩", "导师", "学", "课", "书", "study",
            "learn", "course", "leetcode", "kindle", "知识", "专业", "证书", "驾照", "科目",
        ],
        .life: [
            "猫", "狗", "猫砂", "猫粮", "狗粮", "铲屎", "宠物", "遛狗", "喂", "洗衣", "晾衣", "叠衣服", "打扫", "收拾",
            "整理房间", "拖地", "扫地", "吸尘", "倒垃圾", "垃圾", "做饭", "买菜", "超市", "快递", "取件", "外卖", "洗碗",
            "床单", "被子", "浇花", "浇水", "绿萝", "多肉", "植物", "搬家", "维修", "修理", "网购", "买", "下单", "退货", "理发", "洗车", "加油",
            "停车", "钥匙", "衣服", "鞋", "日用品", "纸巾", "牛奶", "水果", "零食", "冰箱", "家务", "换灯泡", "保洁",
            "物业", "租房", "看房", "车", "地铁", "机票", "火车票", "高铁", "酒店", "行李", "旅行", "签证", "护照",
            "身份证", "缴纳", "电池", "充电", "手机", "电脑", "备份", "groceries", "laundry", "clean",
        ],
        .health: [
            "健身", "跑步", "运动", "锻炼", "瑜伽", "普拉提", "游泳", "骑行", "散步", "徒步", "爬山", "打球", "篮球",
            "羽毛球", "网球", "体检", "医院", "看病", "挂号", "门诊", "牙", "牙医", "洗牙", "吃药", "药", "维生素",
            "喝水", "睡觉", "早睡", "早点睡", "睡眠", "午睡", "冥想", "减肥", "体重", "减脂", "增肌", "拉伸", "步数", "疫苗", "复诊",
            "眼科", "按摩", "理疗", "体能", "深蹲", "俯卧撑", "卡路里", "饮食", "戒烟", "戒糖", "gym",
            "workout", "yoga", "doctor", "running",
        ],
        .finance: [
            "房租", "交租", "租金", "水费", "电费", "燃气费", "物业费", "话费", "网费", "信用卡", "还款", "还钱", "借钱",
            "账单", "报销", "发票", "缴费", "交费", "转账", "工资", "理财", "基金", "股票", "保险", "税", "个税", "贷款",
            "房贷", "车贷", "记账", "预算", "订阅", "续费", "会员", "退款", "花呗", "白条", "公积金", "社保", "存钱",
            "收款", "付款", "汇款", "银行", "支付宝", "rent", "bill", "invoice", "tax", "icloud",
        ],
        .social: [
            "生日", "纪念日", "妈", "爸", "父母", "家人", "爷爷", "奶奶", "外婆", "外公", "姥姥", "姥爷", "哥", "姐",
            "弟", "妹", "朋友", "闺蜜", "兄弟", "聚会", "聚餐", "约饭", "吃饭", "火锅", "饭局", "约会", "婚礼", "份子钱", "礼物", "打电话", "回消息",
            "看望", "探望", "请客", "同学会", "祝福", "女朋友", "男朋友", "老婆", "老公", "对象", "孩子", "宝宝",
            "家长会", "情人节", "春节", "中秋", "过年", "拜年", "红包", "喜酒", "满月", "周年", "birthday",
            "anniversary", "party",
        ],
    ]
}
