import AppKit
import CryptoKit
import Foundation

/// 通过 GitHub Releases 检查和安装更新：
/// 下载 zip → 校验 SHA-256（GitHub 提供）→ 解压并校验签名、Bundle ID、版本号 → 退出后替换自身 → 重新打开。
struct ReleaseInfo: Equatable {
    let version: String
    let title: String
    let notes: String
    let pageURL: URL
    let zipURL: URL?
    let zipSHA256: String?
}

enum UpdateError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case .message(let m) = self { return m }
        return nil
    }
}

final class Updater: ObservableObject {
    static let shared = Updater()
    static let repo = "Cha1ron/CheckLet"

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available
        case downloading(Double)
        case installing
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    /// 可用的新版本（nil = 没有）
    @Published private(set) var latest: ReleaseInfo?
    var onChange: () -> Void = {}

    private var timer: Timer?

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? MCPServer.version
    }

    // MARK: - 检查

    /// 启动 15 秒后检查一次，之后每小时看一眼是否距离上次检查超过 24 小时
    func startAutomaticChecks() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in self?.autoCheckIfDue() }
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in self?.autoCheckIfDue() }
    }

    private func autoCheckIfDue() {
        let d = UserDefaults.standard
        guard d.bool(forKey: Prefs.autoUpdate) else { return }
        let last = d.object(forKey: Prefs.lastUpdateCheck) as? Date ?? .distantPast
        if Date().timeIntervalSince(last) > 23 * 3600 { check(userInitiated: false) }
    }

    func check(userInitiated: Bool) {
        if case .downloading = state { return }
        if state == .installing { return }
        state = .checking
        Task {
            do {
                let info = try await Self.fetchLatest()
                await MainActor.run {
                    UserDefaults.standard.set(Date(), forKey: Prefs.lastUpdateCheck)
                    let skipped = UserDefaults.standard.string(forKey: Prefs.skippedVersion)
                    if Self.isNewer(info.version, than: Self.currentVersion),
                       userInitiated || info.version != skipped {
                        self.latest = info
                        self.state = .available
                    } else {
                        self.latest = nil
                        self.state = .upToDate
                    }
                    self.onChange()
                }
            } catch {
                await MainActor.run {
                    // 自动检查失败（比如没网）就安静地忽略
                    self.state = userInitiated ? .failed(Self.describe(error)) : .idle
                    self.onChange()
                }
            }
        }
    }

    func skipCurrent() {
        guard let v = latest?.version else { return }
        UserDefaults.standard.set(v, forKey: Prefs.skippedVersion)
        latest = nil
        state = .idle
        onChange()
    }

    // MARK: - 安装（App 内）

    func install() {
        guard let info = latest else { return }
        do {
            try Self.checkInstallLocation()
        } catch {
            state = .failed(Self.describe(error))
            return
        }
        state = .downloading(0)
        Task {
            do {
                let newApp = try await Self.prepare(info) { p in
                    DispatchQueue.main.async { self.state = .downloading(p) }
                }
                await MainActor.run {
                    self.state = .installing
                    do {
                        try Self.launchReplacer(newApp: newApp, waitFor: [getpid()], relaunch: true)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { NSApp.terminate(nil) }
                    } catch {
                        self.state = .failed(Self.describe(error))
                    }
                }
            } catch {
                await MainActor.run { self.state = .failed(Self.describe(error)) }
            }
        }
    }

    // MARK: - 通用步骤（App 和命令行共用）

    static func fetchLatest() async throws -> ReleaseInfo {
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("CheckLet/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 20
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else {
            throw UpdateError.message("无法获取版本信息，请稍后再试")
        }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let assets = json["assets"] as? [[String: Any]] ?? []
        let zip = assets.first { ($0["name"] as? String)?.hasSuffix(".zip") == true }
        let digest = (zip?["digest"] as? String).map { $0.replacingOccurrences(of: "sha256:", with: "") }
        return ReleaseInfo(
            version: version,
            title: json["name"] as? String ?? tag,
            notes: json["body"] as? String ?? "",
            pageURL: URL(string: json["html_url"] as? String ?? "") ?? URL(string: "https://github.com/\(repo)/releases")!,
            zipURL: (zip?["browser_download_url"] as? String).flatMap(URL.init(string:)),
            zipSHA256: digest)
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// App 必须在一个可写、稳定的位置（不是安装盘、不是系统的临时隔离目录）
    static func checkInstallLocation() throws {
        let path = Bundle.main.bundleURL.path
        guard path.hasSuffix(".app") else {
            throw UpdateError.message("开发版本不支持自动更新")
        }
        if path.contains("/AppTranslocation/") || path.hasPrefix("/Volumes/") {
            throw UpdateError.message("请先把 CheckLet 移到「应用程序」文件夹，再更新")
        }
        let parent = (path as NSString).deletingLastPathComponent
        guard FileManager.default.isWritableFile(atPath: parent) else {
            throw UpdateError.message("没有权限写入 \(parent)，请到 GitHub 手动下载新版")
        }
    }

    /// 下载、校验、解压，返回准备好的新 .app 路径
    static func prepare(_ info: ReleaseInfo, progress: @escaping (Double) -> Void) async throws -> URL {
        guard let zipURL = info.zipURL else {
            throw UpdateError.message("这个版本没有提供安装包，请到 GitHub 页面下载")
        }
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("CheckLet-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

        // 1. 下载
        let downloaded = try await Downloader.download(zipURL, progress: progress)
        let zipFile = work.appendingPathComponent("update.zip")
        try FileManager.default.moveItem(at: downloaded, to: zipFile)

        // 2. 校验 SHA-256
        if let expected = info.zipSHA256?.lowercased(), !expected.isEmpty {
            let actual = SHA256.hash(data: try Data(contentsOf: zipFile)).map { String(format: "%02x", $0) }.joined()
            guard actual == expected else {
                throw UpdateError.message("安装包校验失败（文件不完整或被篡改），已取消更新")
            }
        }

        // 3. 解压
        let unzipDir = work.appendingPathComponent("unzipped", isDirectory: true)
        guard run("/usr/bin/ditto", ["-x", "-k", zipFile.path, unzipDir.path]).status == 0 else {
            throw UpdateError.message("解压安装包失败")
        }
        let contents = (try? FileManager.default.contentsOfDirectory(at: unzipDir, includingPropertiesForKeys: nil)) ?? []
        guard let newApp = contents.first(where: { $0.pathExtension == "app" }),
              let bundle = Bundle(url: newApp) else {
            throw UpdateError.message("安装包里没有找到 CheckLet.app")
        }

        // 4. 校验身份：同一个 Bundle ID、版本号对得上、代码签名完整
        let currentID = Bundle.main.bundleIdentifier ?? "com.checklet.app"
        guard bundle.bundleIdentifier == currentID else {
            throw UpdateError.message("安装包的应用标识不匹配，已取消更新")
        }
        let newVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        guard newVersion == info.version else {
            throw UpdateError.message("安装包版本号不匹配，已取消更新")
        }
        guard run("/usr/bin/codesign", ["--verify", "--deep", "--strict", newApp.path]).status == 0 else {
            throw UpdateError.message("安装包签名校验失败，已取消更新")
        }
        _ = run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", newApp.path])
        return newApp
    }

    /// 启动一个独立的小脚本：等指定进程退出后替换 App，再重新打开
    static func launchReplacer(newApp: URL, waitFor pids: [pid_t], relaunch: Bool) throws {
        let dest = Bundle.main.bundleURL.path
        let script = """
        NEW="$1"; DEST="$2"; RELAUNCH="$3"; shift 3
        for PID in "$@"; do
          n=0
          while kill -0 "$PID" 2>/dev/null && [ $n -lt 150 ]; do sleep 0.2; n=$((n+1)); done
        done
        BAK="$DEST.updating-$$"
        if mv "$DEST" "$BAK"; then
          if mv "$NEW" "$DEST"; then rm -rf "$BAK"; else mv "$BAK" "$DEST"; fi
        fi
        xattr -dr com.apple.quarantine "$DEST" 2>/dev/null
        [ "$RELAUNCH" = "1" ] && open "$DEST"
        exit 0
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script, "checklet-updater", newApp.path, dest, relaunch ? "1" : "0"] + pids.map(String.init)
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
    }

    static func describe(_ error: Error) -> String {
        if let e = error as? LocalizedError, let d = e.errorDescription { return d }
        if (error as NSError).domain == NSURLErrorDomain { return "网络连接失败，请检查网络后重试" }
        return error.localizedDescription
    }

    @discardableResult
    private static func run(_ exe: String, _ args: [String]) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (-1, "\(error)") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}

/// 带进度的下载
private final class Downloader: NSObject, URLSessionDownloadDelegate {
    private var continuation: CheckedContinuation<URL, Error>?
    private let progress: (Double) -> Void

    private init(progress: @escaping (Double) -> Void) { self.progress = progress }

    static func download(_ url: URL, progress: @escaping (Double) -> Void) async throws -> URL {
        let d = Downloader(progress: progress)
        let session = URLSession(configuration: .ephemeral, delegate: d, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        return try await withCheckedThrowingContinuation { c in
            d.continuation = c
            var req = URLRequest(url: url)
            req.setValue("CheckLet/\(Updater.currentVersion)", forHTTPHeaderField: "User-Agent")
            session.downloadTask(with: req).resume()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData _: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 { progress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // 临时文件在回调返回后就会被删，先挪走
        let keep = FileManager.default.temporaryDirectory.appendingPathComponent("checklet-dl-\(UUID().uuidString).zip")
        do {
            if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 200 {
                throw UpdateError.message("下载失败（HTTP \(http.statusCode)）")
            }
            try FileManager.default.moveItem(at: location, to: keep)
            continuation?.resume(returning: keep)
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}
