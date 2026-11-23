import AppKit
import SwiftUI

struct PanelView: View {
    @ObservedObject var vm: TodoViewModel
    @State private var draft = ""
    @State private var pickedDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var pickedCategory: TodoCategory?
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            tabs
            categoryFilters
            Divider().opacity(0.4).padding(.horizontal, 14)
            list
            if let err = vm.errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .onTapGesture { vm.errorMessage = nil }
            }
            addBar
        }
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
        .onReceive(vm.$focusToken.dropFirst()) { _ in
            DispatchQueue.main.async { inputFocused = true }
        }
    }

    // MARK: 顶部

    private var header: some View {
        HStack(alignment: .center, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Day.shortCN(vm.today))
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                Text("\(Day.weekdayName(vm.today)) · \(summary)")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            IconButton(symbol: vm.pinned ? "pin.fill" : "pin",
                       help: vm.pinned ? "取消固定（鼠标移开后自动隐藏）" : "固定显示",
                       active: vm.pinned) { vm.onTogglePin() }
            IconButton(symbol: "gearshape", help: "设置 / 连接 AI 工具") { vm.onOpenSettings() }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var summary: String {
        let p = vm.todayProgress
        if p.total == 0 { return "今天还没有待办" }
        if p.done == p.total { return "今日待办全部完成 🎉" }
        return "今天还剩 \(p.total - p.done) 件事"
    }

    private var tabs: some View {
        HStack(spacing: 4) {
            ForEach(TodoScope.allCases) { scope in
                let selected = vm.tab == scope
                let count = vm.openCount(scope)
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { vm.tab = scope }
                } label: {
                    HStack(spacing: 4) {
                        Text(scope.title)
                            .font(.system(size: 12.5, weight: selected ? .semibold : .regular))
                        if count > 0 {
                            Text("\(count)")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.primary.opacity(selected ? 0.16 : 0.09), in: Capsule())
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(selected ? Color.primary.opacity(0.12) : Color.clear, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    // MARK: 分类筛选

    @ViewBuilder private var categoryFilters: some View {
        let cats = vm.categoriesInTab
        if cats.count > 1 || vm.categoryFilter != nil {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    FilterChip(text: "全部", color: .secondary, selected: vm.categoryFilter == nil) {
                        vm.categoryFilter = nil
                    }
                    ForEach(cats, id: \.0) { c, open in
                        FilterChip(text: open > 0 ? "\(c.label) \(open)" : c.label, color: c.color,
                                   selected: vm.categoryFilter == c) {
                            vm.categoryFilter = vm.categoryFilter == c ? nil : c
                        }
                    }
                }
                .padding(.horizontal, 14)
            }
            .padding(.bottom, 8)
        }
    }

    // MARK: 列表

    private var list: some View {
        let items = vm.filtered
        return Group {
            if items.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: emptyIcon)
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text(emptyText)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 2) {
                        ForEach(items) { item in
                            TodoRow(item: item, vm: vm)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var emptyIcon: String {
        switch vm.tab {
        case .today: return "sun.max"
        case .week: return "calendar"
        case .date: return "star"
        }
    }

    private var emptyText: String {
        switch vm.tab {
        case .today: return "今天没有待办，享受一下吧\n也可以让 Claude / Codex 帮你加"
        case .week: return "这周还没有计划"
        case .date: return "记下生日、截止日、纪念日\n会显示倒计时"
        }
    }

    // MARK: 添加

    private var addBar: some View {
        HStack(spacing: 8) {
            Button {
                CategoryMenu.show(current: pickedCategory, includeAuto: true) { pickedCategory = $0 }
            } label: {
                Text(pickedCategory?.emoji ?? "✨")
                    .font(.system(size: 13))
                    .frame(width: 22, height: 22)
                    .background(Color.primary.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .help(pickedCategory.map { "分类：\($0.name)" } ?? "分类：自动识别（也可以在内容里写 #生活）")
            TextField(placeholder, text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($inputFocused)
                .onSubmit(submit)
            if vm.tab == .date {
                DatePicker("", selection: $pickedDate, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.field)
                    .frame(width: 96)
                    .font(.system(size: 12))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 12)
    }

    private var placeholder: String {
        switch vm.tab {
        case .today: return "添加今日待办，回车确认"
        case .week: return "添加本周待办，回车确认"
        case .date: return "重要日子，如：妈妈生日"
        }
    }

    private func submit() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        vm.add(text, date: vm.tab == .date ? pickedDate : nil, category: pickedCategory)
        draft = ""
        pickedCategory = nil
    }
}

// MARK: - 单行

struct TodoRow: View {
    let item: TodoItem
    @ObservedObject var vm: TodoViewModel
    @State private var hovering = false
    @State private var editing = false
    @State private var editText = ""
    @FocusState private var editFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button { vm.toggle(item.id) } label: {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(item.done ? Color.green : Color.secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                if editing {
                    TextField("", text: $editText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .focused($editFocused)
                        .onSubmit(commitEdit)
                        .onExitCommand { editing = false }
                } else {
                    Text(item.title)
                        .font(.system(size: 13))
                        .strikethrough(item.done, color: .secondary)
                        .foregroundStyle(item.done ? .secondary : .primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .onTapGesture(count: 2) { startEdit() }
                }
                meta
            }

            Spacer(minLength: 0)

            if hovering && !editing {
                Button { vm.delete(item.id) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("删除")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(hovering ? Color.primary.opacity(0.06) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu { menu }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    @ViewBuilder private var meta: some View {
        let parts = metaParts
        HStack(spacing: 6) {
            CategoryChip(category: item.displayCategory, auto: item.categorySource?.isAuto ?? true) {
                CategoryMenu.show(current: item.category) { if let c = $0 { vm.setCategory(item.id, c) } }
            }
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                Text(part.text)
                    .font(.system(size: 11))
                    .foregroundStyle(part.color)
                    .lineLimit(1)
                    .fixedSize()
            }
            if let src = item.sourceLabel {
                Text(src)
                    .font(.system(size: 9.5, weight: .medium))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.accentColor.opacity(0.18), in: Capsule())
                    .foregroundStyle(.secondary)
            }
        }
        if let note = item.note {
            Text(note)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var metaParts: [(text: String, color: Color)] {
        var out: [(String, Color)] = []
        switch item.scope {
        case .today where item.isCarriedOver(today: vm.today):
            out.append(("从 \(Day.shortCN(item.day)) 顺延", .orange))
        case .week where item.isCarriedOver(today: vm.today):
            out.append(("上周遗留", .orange))
        case .date:
            let n = Day.daysBetween(vm.today, item.day)
            let color: Color = item.done ? .secondary : (n <= 1 ? .red : (n <= 7 ? .orange : .secondary))
            out.append(("\(Day.shortCN(item.day)) \(Day.weekdayName(item.day)) · \(item.countdownText(today: vm.today))", color))
        default: break
        }
        return out
    }

    @ViewBuilder private var menu: some View {
        Button(item.done ? "取消完成" : "完成") { vm.toggle(item.id) }
        Button("编辑") { startEdit() }
        Menu("分类") {
            ForEach(TodoCategory.allCases) { c in
                Button((item.category == c ? "✓ " : "") + c.label) { vm.setCategory(item.id, c) }
            }
        }
        Divider()
        if item.scope == .today {
            Button("推迟到明天") { vm.postpone(item.id) }
        }
        if item.scope != .today { Button("移到今日") { vm.move(item.id, to: .today) } }
        if item.scope != .week { Button("移到本周") { vm.move(item.id, to: .week) } }
        Divider()
        Button("删除", role: .destructive) { vm.delete(item.id) }
    }

    private func startEdit() {
        editText = item.title
        editing = true
        DispatchQueue.main.async { editFocused = true }
    }

    private func commitEdit() {
        let t = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty && t != item.title { vm.rename(item.id, to: t) }
        editing = false
    }
}

struct IconButton: View {
    let symbol: String
    let help: String
    var active = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(active ? Color.accentColor : Color.secondary)
                .frame(width: 26, height: 26)
                .background(hovering ? Color.primary.opacity(0.1) : Color.clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

// MARK: - 分类组件

extension TodoCategory {
    var color: Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

struct CategoryChip: View {
    let category: TodoCategory
    let auto: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(category.label)
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 1.5)
                .foregroundStyle(category.color)
                .background(category.color.opacity(hovering ? 0.28 : 0.16), in: Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(auto ? "自动分类 · 点击修改（会记住你的习惯）" : "点击修改分类")
    }
}

struct FilterChip: View {
    let text: String
    let color: Color
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 11, weight: selected ? .semibold : .regular))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .foregroundStyle(selected ? color : Color.secondary)
                .background(selected ? color.opacity(0.18) : Color.primary.opacity(0.05), in: Capsule())
                .overlay(Capsule().strokeBorder(selected ? color.opacity(0.5) : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// 在鼠标位置弹出分类菜单（原生 NSMenu，在不抢焦点的浮动面板里也能用）
enum CategoryMenu {
    private final class Handler: NSObject {
        let onPick: (TodoCategory?) -> Void
        init(_ onPick: @escaping (TodoCategory?) -> Void) { self.onPick = onPick }
        @objc func pick(_ sender: NSMenuItem) {
            onPick((sender.representedObject as? String).flatMap(TodoCategory.init(rawValue:)))
        }
    }

    static func show(current: TodoCategory?, includeAuto: Bool = false, onPick: @escaping (TodoCategory?) -> Void) {
        let handler = Handler(onPick)
        let menu = NSMenu()
        if includeAuto {
            let auto = NSMenuItem(title: "✨ 自动识别", action: #selector(Handler.pick(_:)), keyEquivalent: "")
            auto.target = handler
            auto.state = current == nil ? .on : .off
            menu.addItem(auto)
            menu.addItem(.separator())
        }
        for c in TodoCategory.allCases {
            let item = NSMenuItem(title: c.label, action: #selector(Handler.pick(_:)), keyEquivalent: "")
            item.target = handler
            item.representedObject = c.rawValue
            item.state = c == current ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        withExtendedLifetime(handler) {}
    }
}
