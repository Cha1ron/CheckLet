import AppKit
import EventKit
import Foundation

/// 把有具体日期的待办同步到系统「日历」里一个叫 CheckLet 的日历，借用日历自带的提醒。
///
/// - 单向同步：CheckLet → 日历。待办改了才会更新对应日程；用户在日历里改 / 删日程，只要待办没变就不会被覆盖或重建
/// - 提醒：全天的当天 9:00；有时间的提前 15 分钟；重要日期再加一个提前一天的提醒
/// - 打勾：日程保留（标题前加 ✓），去掉提醒；删除待办：删除日程
/// - 只有悬浮球 App 会同步（AI 工具通过 MCP 加的待办，App 看到文件变化后同步），
///   这样日历权限只需要授权给 CheckLet 一次
final class CalendarSync: ObservableObject {
    static let shared = CalendarSync()
    static let calendarTitle = "CheckLet"

    enum Status: Equatable {
        case off
        case notDetermined
        case denied
        case syncing
        case synced(calendar: String, count: Int)
        case failed(String)
    }

    @Published private(set) var status: Status = .off

    private let store = EKEventStore()
    private let queue = DispatchQueue(label: "checklet.calendar-sync")
    private var latest: [TodoItem] = []
    private var scheduled = false

    private init() {
        status = enabled ? (Self.hasAccess ? .syncing : .notDetermined) : .off
    }

    var enabled: Bool { UserDefaults.standard.bool(forKey: Prefs.calendarSync) }

    static var hasAccess: Bool {
        let s = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14.0, *) { return s == .fullAccess }
        return s.rawValue == 3 // .authorized（macOS 13）
    }

    private static var isDenied: Bool {
        let s = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14.0, *), s == .writeOnly { return true }
        return s == .denied || s == .restricted
    }

    // MARK: 开关

    func setEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: Prefs.calendarSync)
        guard on else { status = .off; return }
        if Self.hasAccess { sync(latest); return }
        if Self.isDenied { status = .denied; return }
        NSApp.activate(ignoringOtherApps: true)
        let done: (Bool, Error?) -> Void = { [weak self] granted, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                if granted { self.sync(self.latest) } else { self.status = .denied }
            }
        }
        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents(completion: done)
        } else {
            store.requestAccess(to: .event, completion: done)
        }
    }

    static func openPrivacySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!
        NSWorkspace.shared.open(url)
    }

    static func openCalendarApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }

    // MARK: 同步

    /// 待办有变化时调用（主线程）。连续多次变化会合并成一次。
    func sync(_ items: [TodoItem]) {
        latest = items
        guard enabled else { return }
        guard Self.hasAccess else {
            status = Self.isDenied ? .denied : .notDetermined
            return
        }
        guard !scheduled else { return }
        scheduled = true
        queue.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self else { return }
            let items = DispatchQueue.main.sync { () -> [TodoItem] in
                self.scheduled = false
                return self.latest
            }
            let result = self.reconcile(items)
            DispatchQueue.main.async { self.status = result }
        }
    }

    private struct Entry: Codable {
        var eventID: String
        var fingerprint: String
        var done: Bool
    }

    private var mapURL: URL { TodoStore.shared.directory.appendingPathComponent("calendar-sync.json") }

    private func loadMap() -> [String: Entry] {
        guard let data = try? Data(contentsOf: mapURL) else { return [:] }
        return (try? JSONDecoder().decode([String: Entry].self, from: data)) ?? [:]
    }

    private func saveMap(_ map: [String: Entry]) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(map) { try? data.write(to: mapURL, options: .atomic) }
    }

    private func reconcile(_ items: [TodoItem]) -> Status {
        guard let calendar = checkletCalendar() else {
            return .failed("无法创建「\(Self.calendarTitle)」日历")
        }
        let today = Day.today
        var map = loadMap()
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var failures = 0

        // 1. 待办被删除 / 不再有日期 → 删除日程
        for (id, entry) in map {
            if let item = byID[id], item.eventDay != nil { continue }
            // 已完成的待办过几天会被自动清理，这种情况保留日程当作记录
            if byID[id] == nil && entry.done { map[id] = nil; continue }
            if let ev = store.event(withIdentifier: entry.eventID) {
                do { try store.remove(ev, span: .futureEvents, commit: true) } catch { failures += 1; continue }
            }
            map[id] = nil
        }

        // 2. 新增 / 更新
        for item in items {
            guard let day = item.eventDay else { continue }
            let fp = fingerprint(item)
            if let entry = map[item.id] {
                if entry.fingerprint == fp { continue }
                if let ev = store.event(withIdentifier: entry.eventID) {
                    fill(ev, with: item, day: day)
                    do {
                        try store.save(ev, span: .futureEvents, commit: true)
                        map[item.id] = Entry(eventID: ev.eventIdentifier ?? entry.eventID, fingerprint: fp, done: item.done)
                    } catch { failures += 1 }
                    continue
                }
                // 日程在日历里被删了，但待办后来又改过 → 重新建
            } else if item.done || (day < today && !item.isYearly) {
                continue // 刚打开同步时，不给已完成 / 已过期的旧待办补日程
            }
            let ev = EKEvent(eventStore: store)
            ev.calendar = calendar
            fill(ev, with: item, day: day)
            do {
                try store.save(ev, span: .thisEvent, commit: true)
                if let id = ev.eventIdentifier {
                    map[item.id] = Entry(eventID: id, fingerprint: fp, done: item.done)
                }
            } catch { failures += 1 }
        }

        saveMap(map)
        if failures > 0 { return .failed("有 \(failures) 个日程没能写入日历") }
        return .synced(calendar: calendar.title, count: map.count)
    }

    private func fingerprint(_ t: TodoItem) -> String {
        [t.title, t.eventDay ?? "", t.time ?? "", t.done ? "1" : "0", t.isYearly ? "y" : "",
         t.scope.rawValue, t.note ?? ""].joined(separator: "|")
    }

    private func fill(_ ev: EKEvent, with item: TodoItem, day: String) {
        let keepAlarms = !item.done || item.isYearly
        ev.title = (item.done && !item.isYearly ? "✓ " : "") + item.title
        let base = Day.date(day) ?? Date()
        if let time = item.time, let start = Self.date(base, time: time) {
            ev.isAllDay = false
            ev.timeZone = .current
            ev.startDate = start
            ev.endDate = start.addingTimeInterval(3600)
        } else {
            ev.isAllDay = true
            ev.startDate = base
            ev.endDate = base
        }
        var alarms: [EKAlarm] = []
        if keepAlarms {
            if item.time != nil {
                alarms.append(EKAlarm(relativeOffset: -15 * 60))
                if item.scope == .date { alarms.append(EKAlarm(relativeOffset: -24 * 3600)) }
            } else {
                alarms.append(EKAlarm(relativeOffset: 9 * 3600))            // 当天 9:00
                if item.scope == .date { alarms.append(EKAlarm(relativeOffset: -15 * 3600)) } // 前一天 9:00
            }
        }
        ev.alarms = alarms
        ev.recurrenceRules = item.isYearly ? [EKRecurrenceRule(recurrenceWith: .yearly, interval: 1, end: nil)] : nil
        var notes = item.note ?? ""
        if !notes.isEmpty { notes += "\n\n" }
        ev.notes = notes + "来自 CheckLet · \(item.displayCategory.label)"
    }

    private static func date(_ day: Date, time: String) -> Date? {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return Day.calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: day)
    }

    /// 找到（或创建）CheckLet 日历
    private func checkletCalendar() -> EKCalendar? {
        let defaults = UserDefaults.standard
        if let id = defaults.string(forKey: Prefs.calendarID), let cal = store.calendar(withIdentifier: id),
           cal.allowsContentModifications {
            return cal
        }
        if let cal = store.calendars(for: .event).first(where: {
            $0.title == Self.calendarTitle && $0.allowsContentModifications
        }) {
            defaults.set(cal.calendarIdentifier, forKey: Prefs.calendarID)
            return cal
        }
        // 优先建在默认日历所在的账户（通常是 iCloud，手机上也能收到提醒），不行就建在"我的 Mac"本地
        var sources: [EKSource] = []
        if let s = store.defaultCalendarForNewEvents?.source { sources.append(s) }
        sources += store.sources.filter { $0.sourceType == .calDAV && $0.title.lowercased().contains("icloud") }
        sources += store.sources.filter { $0.sourceType == .local }
        for source in sources {
            let cal = EKCalendar(for: .event, eventStore: store)
            cal.title = Self.calendarTitle
            cal.source = source
            cal.cgColor = NSColor(red: 0.96, green: 0.47, blue: 0.62, alpha: 1).cgColor
            if (try? store.saveCalendar(cal, commit: true)) != nil {
                defaults.set(cal.calendarIdentifier, forKey: Prefs.calendarID)
                return cal
            }
        }
        // 实在建不了，就用默认日历
        if let cal = store.defaultCalendarForNewEvents {
            defaults.set(cal.calendarIdentifier, forKey: Prefs.calendarID)
            return cal
        }
        return nil
    }

    var statusText: String {
        switch status {
        case .off: return "未开启"
        case .notDetermined: return "需要授权访问日历"
        case .denied: return "没有日历权限：请在「系统设置 › 隐私与安全性 › 日历」里允许 CheckLet（完全访问）"
        case .syncing: return "同步中…"
        case .synced(let name, let count): return "已同步到「\(name)」日历 · \(count) 个日程"
        case .failed(let msg): return "同步失败：\(msg)"
        }
    }
}
