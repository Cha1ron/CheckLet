import Combine
import Foundation

final class TodoViewModel: ObservableObject {
    @Published private(set) var items: [TodoItem] = []
    @Published private(set) var today: String = Day.today
    @Published var tab: TodoScope = .today {
        didSet { if oldValue != tab { categoryFilter = nil } }
    }
    /// 面板里按分类筛选（nil = 全部）
    @Published var categoryFilter: TodoCategory?
    @Published var pinned: Bool = UserDefaults.standard.bool(forKey: Prefs.pinned) {
        didSet { UserDefaults.standard.set(pinned, forKey: Prefs.pinned) }
    }
    /// 递增一次 = 让输入框获得焦点
    @Published var focusToken = 0
    @Published var errorMessage: String?
    /// 添加后的一句提示，比如「已加到本周 · 11月25日 周三」
    @Published var toast: String?

    var onTogglePin: () -> Void = {}
    var onOpenSettings: () -> Void = {}
    var onClose: () -> Void = {}

    private let store: TodoStore
    private let service: TodoService
    private let smart = SmartClassifier()
    private var lastModified: Date?
    private var timer: Timer?

    init(store: TodoStore = .shared) {
        self.store = store
        self.service = TodoService(store: store)
        _ = try? service.rollYearly()
        reload()
        // 每秒检查一次：数据文件被 AI / 命令行改过就刷新；跨天了也刷新
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.poll() }
        timer?.tolerance = 0.3
    }

    private func poll() {
        let now = Day.today
        if now != today {
            today = now
            _ = try? service.rollYearly(today: now)
            _ = try? service.purgeOldCompleted()
            reload()
            return
        }
        if store.modificationDate != lastModified { reload() }
    }

    func reload() {
        lastModified = store.modificationDate
        let loaded = store.load()
        if loaded != items {
            items = loaded
            CalendarSync.shared.sync(loaded)
        }
        // 旧数据补分类；"关键词猜的"交给 Apple Intelligence 复核（如果可用）
        if loaded.contains(where: { $0.category == nil }) {
            _ = try? service.classifyUncategorized()
            DispatchQueue.main.async { self.reload() }
            return
        }
        smart.refine(loaded, service: service) { [weak self] in self?.reload() }
    }

    // MARK: 读

    func visible(_ scope: TodoScope) -> [TodoItem] { items.visible(scope, today: today) }

    /// 当前标签页 + 分类筛选后的列表
    var filtered: [TodoItem] {
        let list = visible(tab)
        guard let f = categoryFilter else { return list }
        return list.filter { $0.displayCategory == f }
    }

    /// 当前标签页里出现过的分类及未完成数量
    var categoriesInTab: [(TodoCategory, Int)] {
        let list = visible(tab)
        return TodoCategory.allCases.compactMap { c in
            let inCat = list.filter { $0.displayCategory == c }
            return inCat.isEmpty ? nil : (c, inCat.filter { !$0.done }.count)
        }
    }

    /// 本周清单下方：下周已经安排的事
    var nextWeek: [TodoItem] {
        guard tab == .week else { return [] }
        let list = items.nextWeek(today: today)
        guard let f = categoryFilter else { return list }
        return list.filter { $0.displayCategory == f }
    }

    func openCount(_ scope: TodoScope) -> Int { visible(scope).filter { !$0.done }.count }

    var todayProgress: (done: Int, total: Int) {
        let list = visible(.today)
        return (list.filter(\.done).count, list.count)
    }

    /// 今天或明天有未完成的重要日期 → 悬浮球上显示小红点
    var hasUrgentDate: Bool {
        visible(.date).contains { !$0.done && (0...1).contains(Day.daysBetween(today, $0.day)) }
    }

    // MARK: 写

    /// 添加：内容里写了日期（周三、明天下午3点、7月29日…）会自动识别并放进合适的清单
    func add(_ title: String, fallbackDate: Date? = nil, parseDates: Bool = true, category: TodoCategory? = nil) {
        var added: TodoItem?
        perform {
            added = try service.add(title: title, preferredScope: tab, fallbackDate: fallbackDate.map(Day.string),
                                    parseDates: parseDates, source: nil, category: category)
            return added as Any
        }
        guard let item = added else { return }
        let when = Self.whenText(item, today: today)
        if item.scope != tab || when != nil {
            showToast("已加到「\(item.scope.title)」" + (when.map { " · " + $0 } ?? ""))
        }
    }

    private var toastTimer: Timer?
    private func showToast(_ text: String) {
        toast = text
        toastTimer?.invalidate()
        toastTimer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: false) { [weak self] _ in self?.toast = nil }
    }

    /// "11月25日 周三 15:00"、"每年 7月29日"、"下周"
    static func whenText(_ item: TodoItem, today: String) -> String? {
        guard let d = item.eventDay else {
            if item.scope == .week && item.day > Day.weekStart(of: today) { return "下周" }
            return item.time
        }
        return whenText(day: d, time: item.time, yearly: item.isYearly, today: today)
    }

    static func whenText(day d: String, time: String?, yearly: Bool, today: String) -> String {
        let rel: String
        switch Day.daysBetween(today, d) {
        case 0: rel = "今天"
        case 1: rel = "明天"
        default: rel = "\(Day.shortCN(d)) \(Day.weekdayName(d))"
        }
        return (yearly ? "每年 \(Day.shortCN(d))" : rel) + (time.map { " " + $0 } ?? "")
    }

    func setCategory(_ id: String, _ category: TodoCategory) {
        perform { try service.update(id, category: category, categorySource: .user) }
    }

    func toggle(_ id: String) { perform { try service.toggle(id: id) } }
    func delete(_ id: String) { perform { try service.delete(id) } }
    func rename(_ id: String, to title: String) { perform { try service.update(id, title: title) } }
    func move(_ id: String, to scope: TodoScope) { perform { try service.update(id, scope: scope) } }
    func postpone(_ id: String) {
        perform { try service.postpone(id) }
    }

    private func perform(_ body: () throws -> Any) {
        do {
            _ = try body()
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        reload()
    }
}
