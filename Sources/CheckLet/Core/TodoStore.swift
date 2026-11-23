import Foundation

/// 基于 JSON 文件的存储。悬浮球 App、MCP 服务（AI 工具调用）、命令行三者是不同进程，
/// 通过文件锁 (flock) 保证读-改-写不会互相覆盖；App 通过监视文件修改时间来热刷新。
final class TodoStore {
    static let shared = TodoStore()

    let directory: URL
    let fileURL: URL
    private let lockURL: URL

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else if let env = ProcessInfo.processInfo.environment["CHECKLET_DATA_DIR"], !env.isEmpty {
            self.directory = URL(fileURLWithPath: (env as NSString).expandingTildeInPath, isDirectory: true)
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.directory = base.appendingPathComponent("CheckLet", isDirectory: true)
        }
        fileURL = self.directory.appendingPathComponent("todos.json")
        lockURL = self.directory.appendingPathComponent(".lock")
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }()

    var modificationDate: Date? {
        (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.modificationDate] as? Date
    }

    /// 只读加载
    func load() -> [TodoItem] {
        withLock(exclusive: false) { readUnlocked().items }
    }

    /// 加锁后读-改-写
    @discardableResult
    func mutate<T>(_ body: (inout [TodoItem]) throws -> T) throws -> T {
        try withLock(exclusive: true) {
            var file = readUnlocked()
            let result = try body(&file.items)
            let data = try Self.encoder.encode(file)
            try data.write(to: fileURL, options: .atomic)
            return result
        }
    }

    private func readUnlocked() -> TodoFile {
        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else { return TodoFile() }
        do {
            return try Self.decoder.decode(TodoFile.self, from: data)
        } catch {
            // 文件损坏：备份一份，避免覆盖用户数据
            let backup = directory.appendingPathComponent("todos.corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: fileURL, to: backup)
            FileHandle.standardError.write("CheckLet: todos.json 解析失败，已备份到 \(backup.path)\n".data(using: .utf8)!)
            return TodoFile()
        }
    }

    private func withLock<T>(exclusive: Bool, _ body: () throws -> T) rethrows -> T {
        let fd = open(lockURL.path, O_CREAT | O_RDWR, 0o644)
        if fd >= 0 { flock(fd, exclusive ? LOCK_EX : LOCK_SH) }
        defer {
            if fd >= 0 {
                flock(fd, LOCK_UN)
                close(fd)
            }
        }
        return try body()
    }
}
