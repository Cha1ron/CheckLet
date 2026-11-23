import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// 在支持 Apple Intelligence 的 Mac（macOS 26+）上，用端侧模型复核"关键词猜的"分类。
/// 不联网、不花钱；不支持的机器上什么也不做，继续用关键词 + 学习结果。
final class SmartClassifier {
    private var attempted = Set<String>()
    private var running = false

    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    static var statusText: String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return "已启用 Apple Intelligence 端侧模型，自动分类会更准"
            case .unavailable(.deviceNotEligible):
                return "这台 Mac 不支持 Apple Intelligence，使用关键词规则 + 学习你的修正"
            case .unavailable(.appleIntelligenceNotEnabled):
                return "打开「系统设置 → Apple Intelligence」后，自动分类会更准"
            case .unavailable(.modelNotReady):
                return "Apple Intelligence 模型准备中，暂用关键词规则"
            default:
                return "Apple Intelligence 不可用，使用关键词规则 + 学习你的修正"
            }
        }
        #endif
        return "使用关键词规则 + 学习你的修正（macOS 26 且支持 Apple Intelligence 时会更智能）"
    }

    /// 找出需要复核的条目，排队逐条处理
    func refine(_ items: [TodoItem], service: TodoService, onChange: @escaping () -> Void) {
        guard Self.isAvailable, !running else { return }
        let queue = items.filter { $0.categorySource == .rule && !attempted.contains($0.id + $0.title) }
        guard !queue.isEmpty else { return }
        queue.forEach { attempted.insert($0.id + $0.title) }
        running = true
        let examples = service.classifier.examples()

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            Task.detached(priority: .utility) { [weak self] in
                var changed = false
                for item in queue.prefix(30) {
                    if let c = await Self.ask(item.title, examples: examples), c != item.category {
                        try? service.applyModelCategory(id: item.id, title: item.title, category: c)
                        changed = true
                    }
                }
                DispatchQueue.main.async {
                    self?.running = false
                    if changed { onChange() }
                }
            }
            return
        }
        #endif
        running = false
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private static func ask(_ title: String, examples: [(String, TodoCategory)]) async -> TodoCategory? {
        var instructions = "你是待办事项分类助手。把用户给出的一条待办归入下面某一个分类，只回答分类的英文 id，不要任何其他文字。\n"
        instructions += TodoCategory.allCases.map { "\($0.rawValue): \($0.meaning)" }.joined(separator: "\n")
        if !examples.isEmpty {
            instructions += "\n\n这位用户以前的分类习惯（请参考）：\n"
            instructions += examples.map { "「\($0.0)」→ \($0.1.rawValue)" }.joined(separator: "\n")
        }
        do {
            let session = LanguageModelSession(instructions: instructions)
            let reply = try await session.respond(to: "待办：\(title)", options: GenerationOptions(temperature: 0))
            let text = reply.content.lowercased()
            return TodoCategory.allCases.first { text.contains($0.rawValue) }
        } catch {
            return nil
        }
    }
    #endif
}
