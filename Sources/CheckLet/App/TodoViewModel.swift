import Combine
import Foundation

final class TodoViewModel: ObservableObject {
    @Published private(set) var items: [TodoItem] = []
    @Published private(set) var today: String = Day.today
    @Published var tab: TodoScope = .today
    @Published var pinned: Bool = UserDefaults.standard.bool(forKey: Prefs.pinned) {
        didSet { UserDefaults.standard.set(pinned, forKey: Prefs.pinned) }
    }
    /// 递增一次 = 让输入框获得焦点
    @Published var focusToken = 0
    @Published var errorMessage: String?

    var onTogglePin: () -> Void = {}
    var onOpenSettings: () -> Void = {}
    var onClose: () -> Void = {}

    private let store: TodoStore
    private let service: TodoService
    private var lastModified: Date?
    private var timer: Timer?

    init(store: TodoStore = .shared) {
        self.store = store
        self.service = TodoService(store: store)
        reload()
        // 每秒检查一次：数据文件被 AI / 命令行改过就刷新；跨天了也刷新
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.poll() }
        timer?.tolerance = 0.3
    }

    private func poll() {
        let now = Day.today
        if now != today {
            today = now
            _ = try? service.purgeOldCompleted()
            reload()
            return
        }
        if store.modificationDate != lastModified { reload() }
    }

    func reload() {
        lastModified = store.modificationDate
        let loaded = store.load()
        if loaded != items { items = loaded }
    }

    // MARK: 读

    func visible(_ scope: TodoScope) -> [TodoItem] { items.visible(scope, today: today) }

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

    func add(_ title: String, date: Date? = nil) {
        perform { try service.add(title: title, scope: tab, date: date.map(Day.string), source: nil) }
    }

    func toggle(_ id: String) { perform { try service.toggle(id: id) } }
    func delete(_ id: String) { perform { try service.delete(id) } }
    func rename(_ id: String, to title: String) { perform { try service.update(id, title: title) } }
    func move(_ id: String, to scope: TodoScope) { perform { try service.update(id, scope: scope) } }
    func postpone(_ id: String) {
        perform { try service.update(id, date: Day.adding(days: 1, to: today)) }
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
