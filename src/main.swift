import AppKit
import SwiftUI

// MARK: - 本地化

/// 可选语言。`system` 表示跟随系统；其余为 Resources 下的 .lproj 名。
/// 新增语言：加一个 case + displayName，并放入对应 .lproj 即可。
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case zhHans = "zh-Hans"
    case zhHant = "zh-Hant"
    case english = "en"
    case japanese = "ja"
    case korean = "ko"
    case german = "de"
    case french = "fr"
    case spanish = "es"

    var id: String { rawValue }

    /// 语言自称（不随界面语言变化，便于用户识别）
    var displayName: String {
        switch self {
        case .system: return L.s("language.system")
        case .zhHans: return "简体中文"
        case .zhHant: return "繁體中文"
        case .english: return "English"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        case .german: return "Deutsch"
        case .french: return "Français"
        case .spanish: return "Español"
        }
    }

    /// 从已保存的设置读取；非法值回退为跟随系统
    static var saved: AppLanguage {
        let raw = UserDefaults.standard.string(forKey: "AppLanguage") ?? AppLanguage.system.rawValue
        return AppLanguage(rawValue: raw) ?? .system
    }
}

/// 本地化文案入口。所有面向用户的字符串都经此获取，
/// 字符串表位于 Resources/<lang>.lproj/Localizable.strings。
///
/// 应用内切换语言的实现要点（macOS 的 Bundle.main 在进程启动后不会因
/// 写入 AppleLanguages 而改变）：改为直接加载目标 .lproj 子 bundle，
/// 并用与目标语言匹配的 Locale 格式化，否则 .stringsdict 复数规则会失效。
enum L {
    private static var bundle: Bundle = .main
    private static var locale: Locale = .current
    /// 切换语言时自增，供视图 id() 触发重建
    private(set) static var revision = 0

    static func apply(_ language: AppLanguage) {
        switch language {
        case .system:
            bundle = .main
            locale = .current
        default:
            if let path = Bundle.main.path(
                forResource: "Localizable", ofType: "strings",
                inDirectory: nil, forLocalization: language.rawValue),
               let b = Bundle(path: (path as NSString).deletingLastPathComponent) {
                bundle = b
                locale = Locale(identifier: language.rawValue)
            } else {
                bundle = .main
                locale = .current
            }
        }
        revision += 1
    }

    /// 取文案；缺失时回退为 key 本身，便于在界面上一眼发现漏翻
    static func s(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: key, table: nil)
    }

    /// 带格式符的文案（%@ / %lld）
    static func f(_ key: String, _ args: CVarArg...) -> String {
        String(format: s(key), locale: locale, arguments: args)
    }
}

// MARK: - 应用入口

@main
struct MacDroidApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var model = AppModel.shared

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                // 语言切换后强制重建整棵视图树，使已渲染文案重新取值
                .id(model.languageRevision)
        }
        .defaultSize(width: 920, height: 600)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(L.s("menu.about")) { AboutPanel.show() }
            }
            // 单窗口工具，不需要“新建窗口”
            CommandGroup(replacing: .newItem) {}
            // 不声明 Settings 场景：菜单里就不会出现“设置…”入口，
            // 设置入口只放在主界面（齿轮按钮 + adb 胶囊），不在应用菜单里保留
            CommandGroup(after: .toolbar) {
                Button(model.showHiddenFiles ? L.s("menu.hideHidden") : L.s("menu.showHidden")) {
                    model.toggleHiddenFiles()
                }
                .keyboardShortcut(".", modifiers: [.command, .shift])
            }
        }
    }
}

/// 设置独立窗口：由主界面齿轮按钮/adb 胶囊唤起，单例复用
enum SettingsWindow {
    private static var window: NSWindow?
    private static var langObserver: NSObjectProtocol?

    static func show(model: AppModel) {
        if let w = window {
            NSApp.activate(ignoringOtherApps: true)
            w.makeKeyAndOrderFront(nil)
            return
        }
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false)
        w.title = L.s("settings.title")
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: SettingsView(model: model))
        w.center()
        window = w
        // 窗口标题由 AppKit 持有，切换语言后需同步刷新
        langObserver = NotificationCenter.default.addObserver(
            forName: .macDroidLanguageChanged, object: nil, queue: .main
        ) { _ in
            window?.title = L.s("settings.title")
        }
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}

extension Notification.Name {
    static let macDroidLanguageChanged = Notification.Name("MacDroidLanguageChanged")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // 启动时应用已保存的语言偏好
        L.apply(AppLanguage.saved)
        AppModel.shared.languageRevision = L.revision
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}

// MARK: - 关于面板

enum AboutPanel {
    static func show() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "MacDroid"
        alert.informativeText = L.f("about.versionFormat", version)
            + "\n\n" + L.s("about.detail")
        alert.addButton(withTitle: L.s("action.ok"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

// MARK: - 文件模型与展示

struct FileEntry: Identifiable, Hashable {
    let name: String
    let isDirectory: Bool
    let isSymlink: Bool
    let size: Int64?
    let modified: Date?
    /// macOS 的 hidden 标记（如 ~/Library）；点开头条目另行判断
    var isHiddenFlag = false

    var id: String { name }
}

// MARK: - 存储空间与设备信息

/// 卷/分区的容量信息（字节）
struct StorageInfo: Equatable {
    let total: Int64
    let used: Int64
    let available: Int64
    /// 卷名（Mac）或挂载点（设备）
    let label: String?

    var usedFraction: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(used) / Double(total)))
    }
}

/// Android 设备概况。字段按需取，取不到则为 nil（不同 ROM 差异较大）
struct AndroidDeviceInfo: Equatable {
    var brand: String?
    var model: String?
    var androidVersion: String?
    var sdkLevel: String?
    var abi: String?
    var batteryLevel: Int?
    var batteryCharging: Bool?

    /// 「品牌 型号」，去重（部分 ROM 的 model 已含品牌）
    var nameText: String? {
        let b = brand?.trimmingCharacters(in: .whitespaces) ?? ""
        let m = model?.trimmingCharacters(in: .whitespaces) ?? ""
        if b.isEmpty { return m.isEmpty ? nil : m }
        if m.isEmpty { return b }
        return m.lowercased().hasPrefix(b.lowercased()) ? m : "\(b) \(m)"
    }

    var systemText: String? {
        guard let v = androidVersion, !v.isEmpty else { return nil }
        if let s = sdkLevel, !s.isEmpty { return "Android \(v) (API \(s))" }
        return "Android \(v)"
    }
}

/// 字节数格式化（与文件列表口径一致）
func storageSizeText(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

func entrySizeText(_ entry: FileEntry) -> String {
    if entry.isDirectory { return "—" }
    guard let size = entry.size else { return "—" }
    return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
}

func entryDateText(_ entry: FileEntry) -> String {
    guard let date = entry.modified else { return "—" }
    return date.formatted(date: .numeric, time: .shortened)
}

/// SF Symbol 可用性缓存：部分符号仅较新系统提供，缺失时回退，避免图标空白
private var symbolAvailability: [String: Bool] = [:]

private func availableSymbol(_ name: String, fallback: String) -> String {
    if let cached = symbolAvailability[name] {
        return cached ? name : fallback
    }
    let ok = NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    symbolAvailability[name] = ok
    return ok ? name : fallback
}

/// 按扩展名映射图标。只覆盖常见类型，冷门格式统一回退为通用文档图标。
func entrySymbol(_ entry: FileEntry) -> String {
    if entry.isSymlink { return "link" }
    if entry.isDirectory { return "folder.fill" }
    let ext = (entry.name as NSString).pathExtension.lowercased()
    switch ext {
    // 图片（含 RAW 与图标）
    case "jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "bmp", "tif", "tiff",
         "svg", "ico", "avif", "raw", "cr2", "nef", "arw", "dng":
        return "photo"
    // 设计源文件
    case "psd", "ai", "sketch", "fig", "xd", "afdesign":
        return availableSymbol("paintpalette", fallback: "photo")
    // 视频
    // 注：.ts 归入代码（TypeScript 更常见），MPEG-TS 用 .m2ts/.mts
    case "mp4", "mkv", "mov", "avi", "webm", "3gp", "m4v", "mpg", "mpeg",
         "wmv", "flv", "m2ts", "mts", "rmvb":
        return "film"
    // 音频
    case "mp3", "wav", "flac", "aac", "ogg", "m4a", "opus", "wma", "aiff",
         "ape", "alac", "amr", "mid", "midi":
        return "music.note"
    // 压缩包
    case "zip", "rar", "7z", "tar", "gz", "bz2", "xz", "zst", "tgz", "tbz2", "lz4":
        return "doc.zipper"
    // 磁盘镜像 / 安装包
    case "iso", "img", "dmg", "vhd", "vmdk", "qcow2":
        return availableSymbol("opticaldisc", fallback: "externaldrive")
    case "apk", "aab", "xapk", "apks", "ipa":
        return "shippingbox"
    case "exe", "msi", "deb", "rpm", "appimage", "pkg":
        return availableSymbol("cube", fallback: "shippingbox")
    // 办公文档
    case "doc", "docx", "rtf", "odt", "pages":
        return availableSymbol("doc.richtext", fallback: "doc.text")
    case "xls", "xlsx", "ods", "numbers", "tsv":
        return availableSymbol("tablecells", fallback: "doc.text")
    case "ppt", "pptx", "odp", "key":
        return availableSymbol("chart.bar", fallback: "doc.richtext")
    case "pdf":
        return "doc.richtext"
    // 电子书
    case "epub", "mobi", "azw3", "djvu":
        return availableSymbol("book", fallback: "doc.text")
    // 代码 / 配置
    case "swift", "m", "mm", "h", "c", "cpp", "cc", "cs", "java", "kt", "kts",
         "js", "jsx", "ts", "tsx", "py", "rb", "go", "rs", "php", "dart", "lua",
         "scala", "sh", "bash", "zsh", "ps1", "bat", "sql", "r", "vue", "svelte",
         "ipynb", "proto", "graphql":
        return availableSymbol("curlybraces", fallback: "doc.text")
    case "html", "htm", "css", "scss", "sass", "less", "xml", "yaml", "yml",
         "toml", "ini", "conf", "cfg", "env", "plist", "gradle", "properties", "lock":
        return availableSymbol("chevron.left.forwardslash.chevron.right",
                               fallback: "doc.text")
    // 数据 / 文本
    case "json", "jsonl", "ndjson", "csv":
        return availableSymbol("tablecells", fallback: "doc.text")
    case "txt", "md", "markdown", "mdx", "log", "rst", "tex":
        return "doc.text"
    // 字体（用字符方框符号；textformat 会随界面语言渲染成「格式/書式」等文字且超宽）
    case "ttf", "otf", "woff", "woff2", "ttc", "eot":
        return availableSymbol("character.textbox",
                               fallback: availableSymbol("a.circle", fallback: "doc"))
    // 字幕
    case "srt", "ass", "ssa", "vtt", "sub", "idx", "lrc":
        return availableSymbol("captions.bubble", fallback: "doc.text")
    // 可执行 / 库 / 目标文件
    case "o", "a", "so", "dylib", "dll", "lib", "class", "jar", "war", "pyc", "wasm":
        return availableSymbol("cpu", fallback: "doc")
    // 数据库
    case "db", "sqlite", "sqlite3", "mdb", "realm":
        return availableSymbol("cylinder", fallback: "doc")
    // 证书 / 密钥（.key 归入 Keynote，此处不重复）
    case "pem", "crt", "cer", "keystore", "jks", "p12", "pfx", "pub", "asc", "gpg":
        return availableSymbol("key", fallback: "lock")
    // 种子 / 下载中转
    case "torrent":
        return availableSymbol("arrow.down.circle", fallback: "doc")
    case "crdownload", "part", "download", "tmp", "temp", "bak", "swp":
        return availableSymbol("doc.badge.gearshape", fallback: "doc")
    // 邮件
    case "eml", "msg", "mbox":
        return availableSymbol("envelope", fallback: "doc.text")
    // 网页快捷方式 / 联系人 / 日历
    case "webloc", "url", "website":
        return "globe"
    case "vcf", "ics":
        return availableSymbol("calendar", fallback: "doc.text")
    default:
        return "doc"
    }
}

/// 目录在前、同类按名称排序
func sortedEntries(_ entries: [FileEntry]) -> [FileEntry] {
    entries.sorted {
        if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
        return $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }
}

func joinPath(_ base: String, _ name: String) -> String {
    base.hasSuffix("/") ? base + name : base + "/" + name
}

func parentPath(_ path: String) -> String? {
    let trimmed = path.hasSuffix("/") && path.count > 1
        ? String(path.dropLast())
        : path
    guard trimmed != "/" else { return nil }
    let parent = (trimmed as NSString).deletingLastPathComponent
    return parent.isEmpty ? "/" : parent
}

// MARK: - 进程执行

struct ProcessResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

/// 在后台线程执行外部命令（调用方负责不在主线程调用）
func runProcess(_ launchPath: String, _ arguments: [String]) throws -> ProcessResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: launchPath)
    process.arguments = arguments

    let outPipe = Pipe()
    let errPipe = Pipe()
    process.standardOutput = outPipe
    process.standardError = errPipe

    try process.run()
    // 先读后等，避免输出超过管道缓冲区导致死锁
    let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    return ProcessResult(
        exitCode: process.terminationStatus,
        stdout: String(data: outData, encoding: .utf8) ?? "",
        stderr: String(data: errData, encoding: .utf8) ?? ""
    )
}

// MARK: - Shell 路径处理

/// 把设备端路径包成 shell 单引号安全字符串，用于 `adb shell stat/find` 等命令。
/// `adb shell` 会把后续参数拼成一条命令字符串在设备端执行，含空格或非 ASCII 字符的
/// 文件名若不加引号会被拆断，导致 stat 查不到文件、传输进度拿不到已写入大小。
/// 单引号内部无法直接表示单引号，按 `'\''` 转义。
func quotedShellPath(_ path: String) -> String {
    "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

/// 查询设备端单个文件的已写入大小（shell 转义后的 stat）。
/// 返回 nil 表示查询失败（文件尚未创建等），调用方据此保持进度不变。
func remoteFileWrittenBytes(_ adb: String, serial: String, path: String) -> Int64? {
    guard let r = try? runProcess(
            adb, ["-s", serial, "shell", "stat", "-c", "%s", quotedShellPath(path)]),
          r.exitCode == 0 else { return nil }
    return Int64(r.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
}

// MARK: - ADB 桥接

enum ADBError: LocalizedError {
    case notInstalled
    /// 关联本地化 key 与路径参数（渲染时再取值，切换语言后不残留旧文案）
    case manualPathInvalid(String, String)
    case noDevice
    case multipleDevices
    case deviceNotReady(String, String)
    case commandFailed(String)
    /// 目标不是目录（关联路径，渲染时取当前语言）
    case notDirectory(String)
    /// 非 ADB 错误（如 FileManager）：保留原始描述，渲染时原样显示
    case underlying(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return L.s("error.adbMissing")
        case .manualPathInvalid(let key, let path):
            return L.f(key, path)
        case .noDevice:
            return L.s("error.noDevice")
        case .multipleDevices:
            return L.s("error.multipleDevices")
        case .deviceNotReady(let serial, let state):
            return L.f("error.deviceNotReadyFormat", serial, state)
        case .commandFailed(let message):
            return message
        case .notDirectory(let path):
            return L.f("error.notDirectoryFormat", path)
        case .underlying(let message):
            return message
        }
    }
}

struct ADBDevice {
    let serial: String
    let state: String
    let model: String?
}

/// 导航用的设备解析缓存（5s TTL）：避免每次进目录都串行跑 adb devices。
/// 线程安全，供后台加载闭包使用。
final class DeviceCache: @unchecked Sendable {
    static let shared = DeviceCache()
    private let lock = NSLock()
    private var entry: (serial: String, model: String?, at: CFAbsoluteTime)?

    func resolve(_ adb: String) throws -> ADBDevice {
        lock.lock()
        let cached = entry
        lock.unlock()
        if let c = cached, CFAbsoluteTimeGetCurrent() - c.at < 5 {
            return ADBDevice(serial: c.serial, state: "device", model: c.model)
        }
        let device = try ADB.resolveDevice(adb)
        lock.lock()
        entry = (device.serial, device.model, CFAbsoluteTimeGetCurrent())
        lock.unlock()
        return device
    }
}

/// adb 可执行文件的解析结果
struct ADBResolution {
    let path: String?
    /// true = 用户在设置里手动指定；false = 自动探测命中
    let isManual: Bool
    /// 手动指定但不可用时，给出具体原因
    /// 手动路径失效原因：存 (key, 路径参数)，渲染时取当前语言
    let manualProblem: (key: String, path: String)?

    var isAvailable: Bool { path != nil }
}

enum ADB {
    /// 官方引导链接（均为稳定地址）
    static let downloadURL = URL(string: "https://developer.android.com/tools/releases/platform-tools")!
    static let macZipURL = URL(
        string: "https://dl.google.com/android/repository/platform-tools-latest-darwin.zip")!
    static let brewCommand = "brew install --cask android-platform-tools"
    static let pathExportCommand = "export PATH=\"$PATH:$HOME/platform-tools\""

    static var manualPath: String? {
        guard let raw = UserDefaults.standard.string(forKey: "ADBPathOverride") else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// GUI 应用的 PATH 很精简，按常见安装位置逐一探测
    static func candidatePaths() -> [String] {
        let fm = FileManager.default
        var candidates: [String] = [
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb",
            "/usr/bin/adb",
            fm.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Android/sdk/platform-tools/adb").path,
            "/opt/android-sdk/platform-tools/adb",
            "/usr/local/share/android-sdk/platform-tools/adb",
            fm.homeDirectoryForCurrentUser
                .appendingPathComponent("platform-tools/adb").path
        ]
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates += path.split(separator: ":").map { String($0) + "/adb" }
        }
        return candidates
    }

    /// 解析当前生效的 adb：手动优先，其次自动探测
    static func resolve() -> ADBResolution {
        let fm = FileManager.default
        if let manual = manualPath {
            let expanded = (manual as NSString).expandingTildeInPath
            if fm.isExecutableFile(atPath: expanded) {
                return ADBResolution(path: expanded, isManual: true, manualProblem: nil)
            }
            // 手动路径失效时不静默回退，明确告知原因（避免“设置了却没生效”的困惑）。
            // 只存 key+参数，渲染时再取当前语言文案。
            let key = fm.fileExists(atPath: expanded)
                ? "settings.errNotExecutableFormat" : "settings.errNotExistFormat"
            return ADBResolution(path: nil, isManual: true, manualProblem: (key, expanded))
        }
        let hit = candidatePaths().first { fm.isExecutableFile(atPath: $0) }
        return ADBResolution(path: hit, isManual: false, manualProblem: nil)
    }

    static func findExecutable() -> String? { resolve().path }

    /// 读取 adb 版本；同时用于校验手动指定的文件是否真的是 adb
    static func version(_ path: String) -> String? {
        guard let result = try? runProcess(path, ["version"]), result.exitCode == 0 else {
            return nil
        }
        let text = result.stdout.isEmpty ? result.stderr : result.stdout
        guard text.contains("Android Debug Bridge") else { return nil }
        return text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("Version") } ?? text.split(separator: "\n").first.map(String.init)
    }

    /// 校验候选路径：返回 (可用路径, 版本) 或失败原因
    static func validate(path raw: String) -> (path: String, version: String)? {
        let expanded = (raw as NSString).expandingTildeInPath
        guard FileManager.default.isExecutableFile(atPath: expanded) else { return nil }
        guard let v = version(expanded) else { return nil }
        return (expanded, v)
    }

    static func listDevices(_ adb: String) throws -> [ADBDevice] {
        let result = try runProcess(adb, ["devices", "-l"])
        guard result.exitCode == 0 else {
            throw ADBError.commandFailed(
                result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        var devices: [ADBDevice] = []
        for line in result.stdout.split(separator: "\n").dropFirst() {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
                .map(String.init)
            guard fields.count >= 2 else { continue }
            let state = fields[1]
            guard state == "device" || state == "unauthorized" || state == "offline" else {
                continue
            }
            let model = fields.first { $0.hasPrefix("model:") }?
                .replacingOccurrences(of: "model:", with: "")
            devices.append(ADBDevice(serial: fields[0], state: state, model: model))
        }
        return devices
    }

    /// 选定唯一在线设备
    static func resolveDevice(_ adb: String) throws -> ADBDevice {
        let devices = try listDevices(adb)
        guard !devices.isEmpty else { throw ADBError.noDevice }
        guard devices.count == 1 else { throw ADBError.multipleDevices }
        let device = devices[0]
        guard device.state == "device" else {
            throw ADBError.deviceNotReady(device.serial, device.state)
        }
        return device
    }

    /// shell 单引号包裹，防注入/分词
    static func shellQuote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func firstLine(_ text: String) -> String? {
        text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
    }

    /// 设备端新建文件夹（不带 -p：同名已存在时报错而非静默成功）
    static func makeDirectory(_ adb: String, serial: String, path: String) throws {
        let result = try runProcess(adb, ["-s", serial, "shell", "mkdir", shellQuote(path)])
        guard result.exitCode == 0 else {
            throw ADBError.commandFailed(
                firstLine(result.stderr + "\n" + result.stdout) ?? L.f("error.createFolderPathFormat", path))
        }
    }

    /// 设备端删除（rm -rf：目录连同内容删除；符号链接只删链接本身，不跟随）
    static func remove(_ adb: String, serial: String, paths: [String]) throws {
        guard !paths.isEmpty else { return }
        let args = ["-s", serial, "shell", "rm", "-rf"] + paths.map(shellQuote)
        let result = try runProcess(adb, args)
        guard result.exitCode == 0 else {
            throw ADBError.commandFailed(
                firstLine(result.stderr + "\n" + result.stdout) ?? L.s("error.delete"))
        }
    }

    /// 通过 adb shell 列出目录；路径用单引号包裹防止 shell 注入/分词
    static func listDirectory(_ adb: String, serial: String, path: String) throws -> [FileEntry] {
        // 补尾斜杠：/sdcard 这类符号链接不带斜杠时 ls 只列链接本身而非目录内容
        let dirPath = path.hasSuffix("/") ? path : path + "/"
        let quoted = "'" + dirPath.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let result = try runProcess(adb, ["-s", serial, "shell", "ls", "-la", quoted])
        // 先解析再判错：ls 对个别无权 stat 的条目会报 Permission denied 并返回非零退出码，
        // 但 stdout 仍是完整可用的目录列表（如根目录 /）；只有解析不出条目才算失败
        let entries = parseLS(result.stdout)
        if !entries.isEmpty { return entries }
        if result.exitCode == 0 { return [] }
        let message = (result.stderr + "\n" + result.stdout)
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? L.f("error.readDirFormat", dirPath)
        throw ADBError.commandFailed(message)
    }

    /// 设备端文件/目录总字节数（目录递归求和），用作下载进度分母
    /// 读取设备存储容量。用 `df -k`（1K 块）避免 -h 的舍入；
    /// 输出列：Filesystem 1K-blocks Used Available Use% Mounted-on
    static func storage(_ adb: String, serial: String, path: String = "/sdcard") -> StorageInfo? {
        guard let r = try? runProcess(adb, ["-s", serial, "shell", "df", "-k", shellQuote(path)]),
              r.exitCode == 0 else { return nil }
        for line in r.stdout.split(separator: "\n").dropFirst() {
            let f = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            // 有些 ROM 的 Filesystem 名含空格导致列偏移，故从尾部取 Use%/挂载点前的三列
            guard f.count >= 6 else { continue }
            // 定位形如 "42%" 的列，其前三列即 total/used/available
            guard let pctIdx = f.firstIndex(where: { $0.hasSuffix("%") }), pctIdx >= 3 else { continue }
            guard let total = Int64(f[pctIdx - 3]),
                  let used = Int64(f[pctIdx - 2]),
                  let avail = Int64(f[pctIdx - 1]) else { continue }
            let mount = f.count > pctIdx + 1 ? f[(pctIdx + 1)...].joined(separator: " ") : path
            return StorageInfo(total: total * 1024, used: used * 1024,
                               available: avail * 1024, label: mount)
        }
        return nil
    }

    /// 批量读取设备属性 + 电量（单次 adb 往返，约 90ms）。
    /// 用分隔标记切分，缺失字段留空，兼容不同 ROM。
    static func deviceInfo(_ adb: String, serial: String) -> AndroidDeviceInfo? {
        let script = """
        getprop ro.product.brand; echo ---;
        getprop ro.product.model; echo ---;
        getprop ro.build.version.release; echo ---;
        getprop ro.build.version.sdk; echo ---;
        getprop ro.product.cpu.abi; echo ---;
        dumpsys battery | grep -E 'level:|status:'
        """
        guard let r = try? runProcess(adb, ["-s", serial, "shell", script]),
              r.exitCode == 0 else { return nil }
        let parts = r.stdout.components(separatedBy: "---")
        func field(_ i: Int) -> String? {
            guard i < parts.count else { return nil }
            let s = parts[i].trimmingCharacters(in: .whitespacesAndNewlines)
            return s.isEmpty ? nil : s
        }
        var info = AndroidDeviceInfo(
            brand: field(0), model: field(1),
            androidVersion: field(2), sdkLevel: field(3), abi: field(4))
        // 电量段：level: 100 / status: 2(充电) 5(满)
        if parts.count > 5 {
            for line in parts[5].split(separator: "\n") {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("level:") {
                    info.batteryLevel = Int(t.dropFirst(6).trimmingCharacters(in: .whitespaces))
                } else if t.hasPrefix("status:") {
                    let code = Int(t.dropFirst(7).trimmingCharacters(in: .whitespaces)) ?? 0
                    info.batteryCharging = (code == 2 || code == 5)
                }
            }
        }
        // 全空视为不可用
        if info.nameText == nil && info.systemText == nil && info.batteryLevel == nil { return nil }
        return info
    }

    static func remoteTotalBytes(_ adb: String, serial: String, path: String, isDirectory: Bool) -> Int64 {
        if !isDirectory {
            return remoteFileWrittenBytes(adb, serial: serial, path: path) ?? 0
        }
        let quoted = quotedShellPath(path)
        // toybox find 的 -exec 经 adb 二次解析易丢 \;；用 find -print0 | xargs -0 stat 更稳
        let cmd = "find \(quoted) -type f -print0 | xargs -0 stat -c %s"
        guard let r = try? runProcess(adb, ["-s", serial, "shell", cmd]) else { return 0 }
        return r.stdout.split(separator: "\n").reduce(Int64(0)) {
            $0 + (Int64($1.trimmingCharacters(in: .whitespaces)) ?? 0)
        }
    }

    /// 解析 toybox/busybox `ls -la` 输出
    static func parseLS(_ output: String) -> [FileEntry] {
        var entries: [FileEntry] = []
        for rawLine in output.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let first = line.first, "dl-".contains(first) else { continue }
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
                .map(String.init)
            // perms links owner group size date time name...
            guard fields.count >= 8 else { continue }
            let isDir = first == "d"
            let isLink = first == "l"
            var name = fields[7...].joined(separator: " ")
            if isLink, let range = name.range(of: " -> ") {
                name = String(name[..<range.lowerBound])
            }
            guard !name.isEmpty, name != ".", name != ".." else { continue }
            entries.append(FileEntry(
                name: name,
                isDirectory: isDir,
                isSymlink: isLink,
                size: Int64(fields[4]),
                modified: ISODateParser.parse(fields[5] + " " + fields[6])
            ))
        }
        return entries
    }
}

enum ISODateParser {
    static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    static func parse(_ text: String) -> Date? {
        formatter.date(from: text)
    }
}// MARK: - 传输进程（伪终端，获取 adb 实时进度）

struct TransferOutcome {
    let exitCode: Int32
    let output: String
}

/// adb 仅在 stderr 是 TTY 时输出 `[ xx%]` 进度行；用 openpty 提供伪终端。
/// stdout/stderr 合并到同一读取源，避免双管道死锁。调用方须在后台线程调用。
func runTransferProcess(
    _ launchPath: String,
    _ arguments: [String],
    onLine: @escaping (String) -> Void
) throws -> TransferOutcome {
    var master: Int32 = -1
    var slave: Int32 = -1
    var ws = winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0)
    let usePTY = openpty(&master, &slave, nil, nil, &ws) == 0

    let process = Process()
    process.executableURL = URL(fileURLWithPath: launchPath)
    process.arguments = arguments

    let readHandle: FileHandle
    if usePTY {
        let sink = FileHandle(fileDescriptor: slave, closeOnDealloc: false)
        process.standardOutput = sink
        process.standardError = sink
        try process.run()
        close(slave)
        readHandle = FileHandle(fileDescriptor: master, closeOnDealloc: true)
    } else {
        // 回退：无伪终端时 adb 不输出进度行，仅有最终摘要
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        readHandle = pipe.fileHandleForReading
    }

    var text = ""
    var pending = ""
    while true {
        let data = readHandle.availableData
        if data.isEmpty { break }
        pending += String(decoding: data, as: UTF8.self)
        while let idx = pending.firstIndex(where: { $0 == "\r" || $0 == "\n" }) {
            let line = String(pending[..<idx])
            pending.removeSubrange(pending.startIndex...idx)
            if !line.isEmpty {
                text += line + "\n"
                onLine(line)
            }
        }
    }
    if !pending.isEmpty {
        text += pending + "\n"
        onLine(pending)
    }
    process.waitUntilExit()
    return TransferOutcome(exitCode: process.terminationStatus, output: text)
}

func parsePercent(_ line: String) -> Int? {
    guard line.hasPrefix("["), let close = line.firstIndex(of: "]") else { return nil }
    let inner = line[line.index(after: line.startIndex)..<close]
    let digits = inner.trimmingCharacters(in: .whitespaces)
        .replacingOccurrences(of: "%", with: "")
    return Int(digits)
}

// MARK: - 传输队列

enum TransferDirection {
    case upload    // Mac -> Android (adb push)
    case download  // Android -> Mac (adb pull)
}

enum TransferState {
    case queued, running, done, failed
}

struct TransferItem: Identifiable {
    let id = UUID()
    let direction: TransferDirection
    let name: String
    let sourcePath: String
    let destPath: String
    let adb: String
    let serial: String
    let totalBytes: Int64
    let isDirectory: Bool
    var state: TransferState = .queued
    var progress: Double?
    var message: String?
}

/// 源文件/目录总字节数（目录递归求和），用作进度分母
func sourceTotalBytes(_ path: String) -> Int64 {
    let fm = FileManager.default
    var isDir: ObjCBool = false
    guard fm.fileExists(atPath: path, isDirectory: &isDir) else { return 0 }
    if !isDir.boolValue {
        let attrs = try? fm.attributesOfItem(atPath: path)
        return (attrs?[.size] as? Int64) ?? 0
    }
    var total: Int64 = 0
    if let en = fm.enumerator(at: URL(fileURLWithPath: path),
                              includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey]) {
        for case let url as URL in en {
            let v = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
            if v?.isDirectory != true { total += Int64(v?.fileSize ?? 0) }
        }
    }
    return total
}

@MainActor
final class TransferManager: ObservableObject {
    @Published var items: [TransferItem] = []
    /// 单个传输完成后回调（方向, 目标目录），用于刷新对应面板
    var onComplete: ((TransferDirection, String) -> Void)?
    private var running = false

    var activeCount: Int {
        items.filter { $0.state == .queued || $0.state == .running }.count
    }

    func enqueue(_ newItems: [TransferItem]) {
        items.append(contentsOf: newItems)
        pump()
    }

    func clearFinished() {
        items.removeAll { $0.state == .done || $0.state == .failed }
    }

    /// 串行执行：同一时刻只跑一个 adb 传输，其余排队
    private func pump() {
        guard !running, let idx = items.firstIndex(where: { $0.state == .queued }) else { return }
        running = true
        items[idx].state = .running
        let item = items[idx]
        let args = item.direction == .upload
            ? ["-s", item.serial, "push", item.sourcePath, item.destPath]
            : ["-s", item.serial, "pull", item.sourcePath, item.destPath]

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var outcome: TransferOutcome?
            var thrown: String?
            let doneFlag = ProgressFlag()
            // adb 37.x 不输出百分比进度行：轮询目标端已写入大小 / 源总大小 计算真实进度
            let poller = DispatchQueue.global(qos: .utility)
            poller.async {
                let destFile = (item.destPath as NSString)
                    .appendingPathComponent(item.name)
                while !doneFlag.value {
                    var written: Int64 = 0
                    if item.direction == .download {
                        // 本地端：文件取属性大小，目录递归求和（含已写入的部分文件）
                        written = sourceTotalBytes(destFile)
                    } else if item.isDirectory {
                        // 设备端目录：stat 只返回 inode 大小，须递归求和已写入字节
                        written = ADB.remoteTotalBytes(
                            item.adb, serial: item.serial, path: destFile, isDirectory: true)
                    } else {
                        // 设备端单文件：stat -c %s 查已写入大小；路径经 shell 转义，
                        // 避免含空格/非 ASCII 的文件名被拆断导致进度一直为 0。
                        written = remoteFileWrittenBytes(
                            item.adb, serial: item.serial, path: destFile) ?? 0
                    }
                    if item.totalBytes > 0, written > 0 {
                        let frac = min(0.99, Double(written) / Double(item.totalBytes))
                        DispatchQueue.main.async {
                            guard let self,
                                  let i = self.items.firstIndex(where: { $0.id == item.id }),
                                  self.items[i].state == .running
                            else { return }
                            self.items[i].progress = max(self.items[i].progress ?? 0, frac)
                        }
                    }
                    Thread.sleep(forTimeInterval: 0.5)
                }
            }
            do {
                outcome = try runTransferProcess(item.adb, args) { line in
                    // 兼容旧版 adb 的 [ xx%] 进度行
                    guard let pct = parsePercent(line) else { return }
                    DispatchQueue.main.async {
                        guard let self,
                              let i = self.items.firstIndex(where: { $0.id == item.id })
                        else { return }
                        self.items[i].progress = Double(pct) / 100
                    }
                }
            } catch {
                thrown = error.localizedDescription
            }
            doneFlag.value = true
            DispatchQueue.main.async {
                guard let self else { return }
                if let i = self.items.firstIndex(where: { $0.id == item.id }) {
                    if let outcome, outcome.exitCode == 0 {
                        self.items[i].state = .done
                        self.items[i].progress = 1
                        self.items[i].message = outcome.output
                            .split(separator: "\n").last.map(String.init) ?? L.s("status.done")
                    } else {
                        self.items[i].state = .failed
                        self.items[i].message = thrown ?? outcome?.output
                            .split(separator: "\n")
                            .last { !$0.hasPrefix("[") }
                            .map(String.init) ?? L.s("transfer.failed")
                    }
                }
                self.running = false
                // destPath 即目标目录本身，完成后刷新停留于该目录的面板
                self.onComplete?(item.direction, item.destPath)
                self.pump()
            }
        }
    }
}

/// 跨线程停止标志（轮询线程用）
final class ProgressFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = false
    var value: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); _value = newValue; lock.unlock() }
    }
}

// MARK: - 设备状态

enum DeviceStatus: Equatable {
    case detecting
    case adbMissing
    case noDevice
    case unauthorized(String)
    case connected(String)
    case adbPathInvalid
    case error(String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    /// 需要在 Android 栏展示安装/配置引导的状态
    var needsSetupGuide: Bool {
        switch self {
        case .adbMissing, .adbPathInvalid: return true
        default: return false
        }
    }

    var pillText: String {
        switch self {
        case .detecting: return L.s("device.detecting")
        // adb 缺失/路径无效由头部的 adb 胶囊表达，这里只说设备连接状态，避免文案重复
        case .adbMissing, .adbPathInvalid: return L.s("device.disconnected")
        case .noDevice: return L.s("device.disconnected")
        case .unauthorized: return L.s("device.unauthorized")
        case .connected(let label): return L.f("device.connectedFormat", label)
        case .error: return L.s("device.error")
        }
    }

    var pillColor: Color {
        switch self {
        case .connected: return .green
        case .detecting: return .secondary
        case .noDevice, .adbMissing: return .secondary
        case .unauthorized, .error, .adbPathInvalid: return .orange
        }
    }
}

// MARK: - 应用状态

@MainActor
final class AppModel: ObservableObject {
    /// 菜单命令与主界面共享同一实例
    static let shared = AppModel()

    /// 界面语言。切换后立即生效并持久化；languageRevision 自增用于强制重建视图
    /// （SwiftUI 不会因 Bundle 变化自动重绘）。
    @Published var language: AppLanguage = AppLanguage.saved {
        didSet {
            guard language != oldValue else { return }
            UserDefaults.standard.set(language.rawValue, forKey: "AppLanguage")
            L.apply(language)
            languageRevision = L.revision
            NotificationCenter.default.post(name: .macDroidLanguageChanged, object: nil)
        }
    }
    @Published var languageRevision = 0

    /// 安装引导的展开状态。安装 adb 属低频操作，默认收起；
    /// 检测到 adb 缺失/路径失效时自动展开，保证需要时可见。
    @Published var guideExpanded = false

    // Mac 侧
    @Published var macPath: String
    @Published var macEntries: [FileEntry] = []
    @Published var macLoading = false
    @Published var macError: ADBError?
    /// Mac 所在卷的容量
    @Published var macStorage: StorageInfo?
    /// Android 存储与设备概况
    @Published var androidStorage: StorageInfo?
    @Published var androidInfo: AndroidDeviceInfo?

    // Android 侧
    @Published var androidPath = "/sdcard/"
    @Published var androidEntries: [FileEntry] = []
    @Published var androidLoading = false
    @Published var androidError: ADBError?
    @Published var deviceStatus: DeviceStatus = .detecting {
        didSet {
            // 折叠联动放在这里，覆盖所有赋值路径（refreshAndroid / loadAndroid / 启动）。
            // adb 缺失或路径失效时自动展开引导，恢复正常后收起。
            guard deviceStatus != oldValue else { return }
            if deviceStatus.needsSetupGuide {
                guideExpanded = true
            } else if case .connected = deviceStatus {
                guideExpanded = false
            }
            // 连接建立时拉取存储/设备概况；断开则清空
            if deviceStatus.isConnected {
                refreshAndroidInfo()
            } else {
                androidStorage = nil
                androidInfo = nil
            }
        }
    }

    // 选择与传输
    @Published var macSelection = Set<String>()
    @Published var androidSelection = Set<String>()
    let transfers = TransferManager()

    /// Mac 侧是否显示隐藏文件（点开头条目），默认关闭，选择持久化
    @Published var showHiddenFiles: Bool = UserDefaults.standard.bool(forKey: "ShowHiddenFiles") {
        didSet {
            guard showHiddenFiles != oldValue else { return }
            UserDefaults.standard.set(showHiddenFiles, forKey: "ShowHiddenFiles")
            reloadMacEntries()
        }
    }
    /// 保留未过滤的原始条目，切换开关时无需重新读盘
    private var macAllEntries: [FileEntry] = []

    private var macToken = UUID()
    private var androidToken = UUID()
    private var detectToken = UUID()

    init() {
        let defaults = UserDefaults.standard
        let fm = FileManager.default
        // 恢复上次浏览的目录（主流文件管理器行为）；Mac 路径失效时回退 home
        if let saved = defaults.string(forKey: "LastMacPath"),
           fm.fileExists(atPath: saved) {
            macPath = saved
        } else {
            macPath = fm.homeDirectoryForCurrentUser.path
        }
        if let saved = defaults.string(forKey: "LastAndroidPath"), !saved.isEmpty {
            androidPath = saved
        }
        transfers.onComplete = { [weak self] direction, destDir in
            guard let self else { return }
            switch direction {
            case .upload:
                // 上传完成：若设备面板正停留在目标目录，刷新它
                if self.androidPath == destDir || self.androidPath == destDir + "/" {
                    self.refreshAndroid()
                }
                self.refreshAndroidInfo()   // 容量已变化
            case .download:
                // 下载完成：若 Mac 面板正停留在目标目录，刷新它
                if self.macPath == destDir {
                    self.refreshMac()
                }
                self.refreshMacStorage()
            }
        }
        refreshMac()
        refreshAndroid()
    }

    // MARK: 传输

    func uploadSelection() {
        let selected = macEntries.filter { macSelection.contains($0.name) }
        guard !selected.isEmpty else { return }
        guard deviceStatus.isConnected else {
            presentAlert(L.s("device.disconnected"), L.s("error.connectDevice"))
            return
        }
        guard let adb = ADB.findExecutable(),
              let device = try? ADB.resolveDevice(adb) else {
            presentAlert(L.s("error.deviceUnavailable"), L.s("error.refreshRetry"))
            return
        }
        let destDir = androidPath.hasSuffix("/") ? androidPath : androidPath + "/"
        let existing = Set(androidEntries.map(\.name))
        let collisions = selected.map(\.name).filter { existing.contains($0) }
        if !collisions.isEmpty {
            let preview = collisions.prefix(5).joined(separator: L.s("delete.nameSeparator"))
            let more = collisions.count > 5 ? L.f("overwrite.moreFormat", collisions.count) : ""
            guard confirmOverwrite(
                L.f("overwrite.deviceFormat", preview, more))
            else { return }
        }
        let items = selected.map { entry in
            TransferItem(
                direction: .upload, name: entry.name,
                sourcePath: joinPath(macPath, entry.name),
                destPath: destDir, adb: adb, serial: device.serial,
                totalBytes: sourceTotalBytes(joinPath(macPath, entry.name)),
                isDirectory: entry.isDirectory)
        }
        transfers.enqueue(items)
    }

    func downloadSelection() {
        let selected = androidEntries.filter { androidSelection.contains($0.name) }
        guard !selected.isEmpty else { return }
        guard deviceStatus.isConnected else {
            presentAlert(L.s("device.disconnected"), L.s("error.connectDevice"))
            return
        }
        guard let adb = ADB.findExecutable(),
              let device = try? ADB.resolveDevice(adb) else {
            presentAlert(L.s("error.deviceUnavailable"), L.s("error.refreshRetry"))
            return
        }
        let existing = Set(macEntries.map(\.name))
        let collisions = selected.map(\.name).filter { existing.contains($0) }
        if !collisions.isEmpty {
            let preview = collisions.prefix(5).joined(separator: L.s("delete.nameSeparator"))
            let more = collisions.count > 5 ? L.f("overwrite.moreFormat", collisions.count) : ""
            guard confirmOverwrite(
                L.f("overwrite.macFormat", preview, more))
            else { return }
        }
        let items = selected.map { entry in
            TransferItem(
                direction: .download, name: entry.name,
                sourcePath: joinPath(androidPath, entry.name),
                destPath: macPath, adb: adb, serial: device.serial,
                totalBytes: ADB.remoteTotalBytes(
                    adb, serial: device.serial,
                    path: joinPath(androidPath, entry.name),
                    isDirectory: entry.isDirectory),
                isDirectory: entry.isDirectory)
        }
        transfers.enqueue(items)
    }

    private func confirmOverwrite(_ text: String) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L.s("overwrite.title")
        alert.informativeText = text
        alert.addButton(withTitle: L.s("action.overwrite"))
        alert.addButton(withTitle: L.s("action.cancel"))
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func presentAlert(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = text
        alert.addButton(withTitle: L.s("action.ok"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // MARK: 新建文件夹 / 删除

    func createMacFolder() {
        guard let name = promptFolderName(existing: Set(macEntries.map(\.name))) else { return }
        let path = joinPath(macPath, name)
        do {
            try FileManager.default.createDirectory(
                atPath: path, withIntermediateDirectories: false)
            refreshMac()
        } catch {
            presentAlert(L.s("error.createFolder"), error.localizedDescription)
        }
    }

    func createAndroidFolder() {
        guard deviceStatus.isConnected else {
            presentAlert(L.s("device.disconnected"), L.s("error.connectDevice"))
            return
        }
        guard let name = promptFolderName(existing: Set(androidEntries.map(\.name))) else { return }
        guard let adb = ADB.findExecutable(),
              let device = try? ADB.resolveDevice(adb) else {
            presentAlert(L.s("error.deviceUnavailable"), L.s("error.refreshRetry"))
            return
        }
        let path = joinPath(androidPath, name)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var message: String?
            do {
                try ADB.makeDirectory(adb, serial: device.serial, path: path)
            } catch {
                message = error.localizedDescription
            }
            DispatchQueue.main.async {
                guard let self else { return }
                if let message {
                    self.presentAlert(L.s("error.createFolder"), message)
                } else {
                    self.refreshAndroid()
                }
            }
        }
    }

    func deleteMacSelection() {
        let selected = macEntries.filter { macSelection.contains($0.name) }
        guard !selected.isEmpty else { return }
        let dirCount = selected.filter { $0.isDirectory }.count
        var text = L.f("delete.itemsFormat", selected.count)
        if dirCount > 0 { text += L.f("delete.foldersFormat", dirCount) }
        text += L.s("delete.listSeparator")
            + selected.prefix(8).map(\.name).joined(separator: L.s("delete.nameSeparator"))
        if selected.count > 8 { text += L.s("delete.etc") }
        text += L.s("delete.trashRecoverable")
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L.s("delete.trashTitle")
        alert.informativeText = text
        alert.addButton(withTitle: L.s("action.moveToTrash"))
        alert.addButton(withTitle: L.s("action.cancel"))
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let urls = selected.map { URL(fileURLWithPath: joinPath(macPath, $0.name)) }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var failures: [String] = []
            for url in urls {
                do {
                    try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                } catch {
                    failures.append(L.f("error.itemReasonFormat", url.lastPathComponent, error.localizedDescription))
                }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.refreshMac()
                if !failures.isEmpty {
                    self.presentAlert(L.s("delete.partialFail"), failures.joined(separator: "\n"))
                }
            }
        }
    }

    func deleteAndroidSelection() {
        let selected = androidEntries.filter { androidSelection.contains($0.name) }
        guard !selected.isEmpty, deviceStatus.isConnected else { return }
        let dirCount = selected.filter { $0.isDirectory }.count
        var text = L.f("delete.itemsFormat", selected.count)
        if dirCount > 0 { text += L.f("delete.foldersFormat", dirCount) }
        text += L.s("delete.listSeparator")
            + selected.prefix(8).map(\.name).joined(separator: L.s("delete.nameSeparator"))
        if selected.count > 8 { text += L.s("delete.etc") }
        text += L.s("delete.irreversible")
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = L.s("delete.foreverTitle")
        alert.informativeText = text
        alert.addButton(withTitle: L.s("action.deleteForever"))
        alert.addButton(withTitle: L.s("action.cancel"))
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let adb = ADB.findExecutable(),
              let device = try? ADB.resolveDevice(adb) else {
            presentAlert(L.s("error.deviceUnavailable"), L.s("error.refreshRetry"))
            return
        }
        let paths = selected.map { joinPath(androidPath, $0.name) }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var message: String?
            do {
                try ADB.remove(adb, serial: device.serial, paths: paths)
            } catch {
                message = error.localizedDescription
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.refreshAndroid()
                if let message {
                    self.presentAlert(L.s("error.delete"), message)
                }
            }
        }
    }

    /// 新建文件夹弹窗：名称校验（非空、不含 /、不为 . / ..、不与现有条目重名）。
    /// 校验失败时重建弹窗并保留上次输入，避免复用已关闭的 NSAlert。
    private func promptFolderName(existing: Set<String>) -> String? {
        var lastInput = ""
        var problem: String?
        while true {
            let alert = NSAlert()
            alert.messageText = L.s("action.newFolder")
            alert.informativeText = problem ?? L.s("newFolder.prompt")
            alert.addButton(withTitle: L.s("action.create"))
            alert.addButton(withTitle: L.s("action.cancel"))
            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
            field.placeholderString = L.s("newFolder.placeholder")
            field.stringValue = lastInput
            alert.accessoryView = field
            NSApp.activate(ignoringOtherApps: true)
            alert.window.initialFirstResponder = field
            guard alert.runModal() == .alertFirstButtonReturn else { return nil }
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            lastInput = name
            if name.isEmpty {
                problem = L.s("newFolder.errEmpty")
                continue
            }
            if name == "." || name == ".." || name.contains("/") {
                problem = L.s("newFolder.errInvalid")
                continue
            }
            if existing.contains(name) {
                problem = L.f("newFolder.errExistsFormat", name)
                continue
            }
            return name
        }
    }

    // MARK: 选择（单击单选 / Cmd 加选减选 / Shift 范围选）
    // 不用 List 内置 selection：行上的双击手势会吞掉内置单击选择，故手动管理。

    private var macAnchor: String?
    private var androidAnchor: String?

    func selectMac(_ entry: FileEntry) {
        macSelection = applySelection(
            entry, entries: macEntries, current: macSelection, anchor: &macAnchor)
    }

    func selectAndroid(_ entry: FileEntry) {
        androidSelection = applySelection(
            entry, entries: androidEntries, current: androidSelection, anchor: &androidAnchor)
    }

    private func applySelection(
        _ entry: FileEntry, entries: [FileEntry],
        current: Set<String>, anchor: inout String?
    ) -> Set<String> {
        var result = current
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if result.contains(entry.name) { result.remove(entry.name) }
            else { result.insert(entry.name) }
            anchor = entry.name
        } else if flags.contains(.shift), let anchor,
                  let i = entries.firstIndex(where: { $0.name == anchor }),
                  let j = entries.firstIndex(where: { $0.name == entry.name }) {
            result = Set(entries[min(i, j)...max(i, j)].map(\.name))
        } else {
            result = [entry.name]
            anchor = entry.name
        }
        return result
    }

    // MARK: Mac 侧

    func refreshMac() {
        loadMac(at: macPath)
        refreshMacStorage()
    }

    /// 读取 Mac 所在卷容量。用 ForImportantUsage（与 Finder「可用」口径一致，
    /// 计入可清除空间），取不到时回退普通可用容量。
    func refreshMacStorage() {
        let path = macPath
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let keys: [URLResourceKey] = [
                .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey, .volumeNameKey
            ]
            var info: StorageInfo?
            if let v = try? URL(fileURLWithPath: path).resourceValues(forKeys: Set(keys)),
               let total = v.volumeTotalCapacity {
                let avail = v.volumeAvailableCapacityForImportantUsage
                    ?? Int64(v.volumeAvailableCapacity ?? 0)
                let t = Int64(total)
                info = StorageInfo(total: t, used: max(0, t - avail),
                                   available: avail, label: v.volumeName)
            }
            DispatchQueue.main.async { self?.macStorage = info }
        }
    }

    /// 读取设备存储与概况（两次 adb 往返，约 0.2s，放后台）
    func refreshAndroidInfo() {
        guard deviceStatus.isConnected else {
            androidStorage = nil
            androidInfo = nil
            return
        }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let adb = ADB.findExecutable(),
                  let dev = try? ADB.resolveDevice(adb) else { return }
            let storage = ADB.storage(adb, serial: dev.serial)
            let info = ADB.deviceInfo(adb, serial: dev.serial)
            DispatchQueue.main.async {
                guard let self, self.deviceStatus.isConnected else { return }
                self.androidStorage = storage
                self.androidInfo = info
            }
        }
    }

    func enterMacDirectory(_ entry: FileEntry) {
        guard entry.isDirectory else { return }
        loadMac(at: joinPath(macPath, entry.name))
    }

    func macGoUp() {
        guard let parent = parentPath(macPath) else { return }
        loadMac(at: parent)
    }

    /// 面包屑跳转：直接定位到指定绝对路径（同路径不重复加载）
    func navigateMac(to path: String) {
        guard path != macPath else { return }
        loadMac(at: path)
    }

    func chooseMacFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: macPath)
        panel.prompt = L.s("action.open")
        panel.message = L.s("panel.chooseFolder")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadMac(at: url.path)
    }

    /// 在 Finder 中显示：
    /// - 有选中项：在 Finder 中定位并高亮这些项（reveal 语义，会打开其所在目录）
    /// - 无选中项：直接打开当前目录本身
    ///   （activateFileViewerSelecting 对目录是“揭示”语义，会打开父目录并选中它，
    ///    因此这里必须用 open，否则用户看到的是上一级）
    /// 只操作 Mac 侧路径，不涉及设备。
    func showMacInFinder() {
        let fm = FileManager.default
        let selected = macEntries.filter { macSelection.contains($0.name) }
        if selected.isEmpty {
            guard fm.fileExists(atPath: macPath) else {
                presentAlert(L.s("error.finderUnavailable"), L.s("error.pathGone"))
                refreshMac()
                return
            }
            NSWorkspace.shared.open(URL(fileURLWithPath: macPath))
            return
        }
        let urls = selected.map { URL(fileURLWithPath: joinPath(macPath, $0.name)) }
        // 过滤已不存在的条目（例如刚被外部删除），避免 Finder 无响应
        let existing = urls.filter { fm.fileExists(atPath: $0.path) }
        guard !existing.isEmpty else {
            presentAlert(L.s("error.finderUnavailable"), L.s("error.pathGone"))
            refreshMac()
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting(existing)
    }

    private func loadMac(at path: String) {
        macToken = UUID()
        let token = macToken
        macLoading = true
        macError = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var entries: [FileEntry] = []
            var loadError: ADBError?
            do {
                let fm = FileManager.default
                let url = URL(fileURLWithPath: path)
                let keys: [URLResourceKey] = [
                    .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey,
                    .contentModificationDateKey, .isHiddenKey
                ]
                let urls = try fm.contentsOfDirectory(
                    at: url, includingPropertiesForKeys: keys, options: [])
                for item in urls {
                    let values = try? item.resourceValues(forKeys: Set(keys))
                    entries.append(FileEntry(
                        name: item.lastPathComponent,
                        isDirectory: values?.isDirectory ?? false,
                        isSymlink: values?.isSymbolicLink ?? false,
                        size: values?.fileSize.map(Int64.init),
                        modified: values?.contentModificationDate,
                        isHiddenFlag: values?.isHidden ?? false
                    ))
                }
            } catch {
                loadError = (error as? ADBError) ?? .underlying(error.localizedDescription)
            }
            let result = sortedEntries(entries)
            DispatchQueue.main.async {
                guard let self, self.macToken == token else { return }
                self.macPath = path
                self.macAllEntries = result
                self.macEntries = self.visibleMacEntries(result)
                self.macSelection = []
                self.macError = loadError
                self.macLoading = false
                // 目录可能位于其他卷（如外置盘），导航后重取该卷容量
                self.refreshMacStorage()
                if loadError == nil {
                    UserDefaults.standard.set(path, forKey: "LastMacPath")
                }
            }
        }
    }

    /// 按开关过滤隐藏条目，口径与 Finder 一致：
    /// 点开头（.gradle 等）+ 带 hidden 标记（~/Library 等）
    private func visibleMacEntries(_ entries: [FileEntry]) -> [FileEntry] {
        showHiddenFiles
            ? entries
            : entries.filter { !$0.name.hasPrefix(".") && !$0.isHiddenFlag }
    }

    private func reloadMacEntries() {
        macEntries = visibleMacEntries(macAllEntries)
        // 移除已不可见条目的选中态，避免对隐藏项误操作
        let visible = Set(macEntries.map(\.name))
        macSelection = macSelection.intersection(visible)
    }

    func toggleHiddenFiles() {
        showHiddenFiles.toggle()
    }

    var macPathDisplay: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if macPath == home { return "~" }
        if macPath.hasPrefix(home + "/") { return "~" + macPath.dropFirst(home.count) }
        return macPath
    }

    // MARK: adb 路径设置

    /// 当前生效的 adb 路径（nil = 不可用）
    @Published var adbPath: String?
    @Published var adbVersion: String?
    @Published var adbIsManual = false
    @Published var adbProblem: (key: String, path: String)?
    /// 设置窗口输入框内容
    @Published var adbPathInput: String = ADB.manualPath ?? ""
    @Published var adbValidating = false
    @Published var adbValidationMessage: String?
    /// 校验结果是否为成功（决定提示颜色，避免靠文案前缀判断）
    @Published var adbValidationOK = false

    // MARK: 主界面 adb 状态胶囊

    var adbPillText: String {
        if adbPath != nil { return L.s("adb.detected") }
        return adbIsManual ? L.s("adb.invalidPath") : L.s("adb.missing")
    }

    var adbPillColor: Color {
        if adbPath != nil { return .green }
        return adbIsManual ? .red : .secondary
    }

    /// 重新解析 adb 并读取版本（后台执行，避免阻塞主线程）
    func refreshADBInfo() {
        let resolution = ADB.resolve()
        adbPath = resolution.path
        adbIsManual = resolution.isManual
        adbProblem = resolution.manualProblem
        adbVersion = nil
        guard let path = resolution.path else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let v = ADB.version(path)
            DispatchQueue.main.async {
                guard let self, self.adbPath == path else { return }
                self.adbVersion = v
            }
        }
    }

    /// 应用手动路径：先校验确实是 adb，再写入偏好并重新探测设备
    func applyManualADBPath(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            adbValidationMessage = L.s("settings.errEmptyPath")
            adbValidationOK = false
            return
        }
        let expanded = (trimmed as NSString).expandingTildeInPath
        adbValidating = true
        adbValidationMessage = nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let fm = FileManager.default
            var failure: String?
            if !fm.fileExists(atPath: expanded) {
                failure = L.f("settings.errNotExistFormat", expanded)
            } else if !fm.isExecutableFile(atPath: expanded) {
                failure = L.f("settings.errNotExecutableFormat", expanded)
            } else if ADB.version(expanded) == nil {
                failure = L.f("settings.errNotADBFormat", expanded)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.adbValidating = false
                if let failure {
                    self.adbValidationMessage = failure
                    self.adbValidationOK = false
                    return
                }
                UserDefaults.standard.set(expanded, forKey: "ADBPathOverride")
                self.adbPathInput = expanded
                self.adbValidationMessage = L.s("settings.applied")
                self.adbValidationOK = true
                self.refreshADBInfo()
                self.refreshAndroid()
            }
        }
    }

    /// 恢复自动探测
    func resetADBPathToAuto() {
        UserDefaults.standard.removeObject(forKey: "ADBPathOverride")
        adbPathInput = ""
        adbValidationMessage = nil
        refreshADBInfo()
        refreshAndroid()
    }

    /// 用 NSOpenPanel 选择 adb 可执行文件
    func chooseADBExecutable() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.message = L.s("settings.chooseADB")
        panel.prompt = L.s("action.select")
        let current = adbPath ?? ADB.manualPath
        if let current {
            panel.directoryURL = URL(fileURLWithPath: current)
                .deletingLastPathComponent()
        }
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        adbPathInput = url.path
        applyManualADBPath(url.path)
    }

    // MARK: Android 侧

    func refreshAndroid() {
        androidToken = UUID()
        detectToken = UUID()
        let token = androidToken
        let dToken = detectToken
        androidLoading = true
        androidError = nil
        deviceStatus = .detecting
        let path = androidPath.hasSuffix("/") ? androidPath : androidPath + "/"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var status: DeviceStatus = .detecting
            var entries: [FileEntry]?
            var loadError: ADBError?
            var pathFallback = false
            do {
                let resolution = ADB.resolve()
                guard let adb = resolution.path else {
                    if let problem = resolution.manualProblem {
                        throw ADBError.manualPathInvalid(problem.key, problem.path)
                    }
                    throw ADBError.notInstalled
                }
                let device = try ADB.resolveDevice(adb)
                status = .connected(device.model ?? device.serial)
                do {
                    let listed = sortedEntries(
                        try ADB.listDirectory(adb, serial: device.serial, path: path))
                    if listed.count == 1, let only = listed.first,
                       only.name == (path as NSString).lastPathComponent,
                       !only.isDirectory {
                        loadError = .notDirectory(path)
                        pathFallback = true
                    } else {
                        entries = listed
                    }
                } catch {
                    // 设备已连接、仅当前目录不可读（例如记忆目录已被删除）：
                    // 保持已连接状态并回退到内部存储根目录，避免“重试仍是坏路径”的死锁
                    pathFallback = true
                    loadError = (error as? ADBError) ?? .underlying(error.localizedDescription)
                }
            } catch let error as ADBError {
                switch error {
                case .notInstalled: status = .adbMissing
                case .manualPathInvalid: status = .adbPathInvalid
                case .noDevice: status = .noDevice
                case .deviceNotReady(_, let state): status = .unauthorized(state)
                default: status = .error(error.localizedDescription)
                }
                loadError = error
            } catch {
                status = .error(error.localizedDescription)
                loadError = (error as? ADBError) ?? .underlying(error.localizedDescription)
            }
            DispatchQueue.main.async {
                guard let self, self.androidToken == token, self.detectToken == dToken
                else { return }
                self.deviceStatus = status
                self.refreshADBInfo()
                // didSet 只在状态「变化」时触发；已连接时点刷新状态不变，
                // 需在此显式重取容量/电量，否则数值不更新
                if status.isConnected { self.refreshAndroidInfo() }
                if let entries {
                    self.androidPath = path
                    self.androidEntries = entries
                    self.androidSelection = []
                    self.androidError = nil
                    UserDefaults.standard.set(path, forKey: "LastAndroidPath")
                } else if pathFallback, status.isConnected, path != "/sdcard/" {
                    // 记忆目录失效：回退到内部存储根目录，用户可继续浏览
                    self.androidError = nil
                    self.loadAndroid(at: "/sdcard/")
                    return
                } else {
                    self.androidEntries = []
                    self.androidSelection = []
                    self.androidError = loadError
                }
                self.androidLoading = false
            }
        }
    }

    func enterAndroidDirectory(_ entry: FileEntry) {
        guard entry.isDirectory || entry.isSymlink, deviceStatus.isConnected else { return }
        loadAndroid(at: joinPath(androidPath, entry.name))
    }

    func androidGoUp() {
        guard let parent = parentPath(androidPath), deviceStatus.isConnected else { return }
        loadAndroid(at: parent)
    }

    /// 面包屑跳转：直接定位到设备上的指定绝对路径
    func navigateAndroid(to path: String) {
        guard deviceStatus.isConnected else { return }
        let normalized = path.hasSuffix("/") ? path : path + "/"
        guard normalized != androidPath else { return }
        loadAndroid(at: normalized)
    }

    private func loadAndroid(at path: String) {
        // 统一尾斜杠：/sdcard 等符号链接目录不带斜杠时 ls 只列链接本身
        let path = path.hasSuffix("/") ? path : path + "/"
        androidToken = UUID()
        let token = androidToken
        androidLoading = true
        androidError = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var entries: [FileEntry]?
            var loadError: ADBError?
            var needsGuide = false
            do {
                let resolution = ADB.resolve()
                guard let adb = resolution.path else {
                    if let problem = resolution.manualProblem {
                        throw ADBError.manualPathInvalid(problem.key, problem.path)
                    }
                    throw ADBError.notInstalled
                }
                let device = try DeviceCache.shared.resolve(adb)
                do {
                    let listed = sortedEntries(
                        try ADB.listDirectory(adb, serial: device.serial, path: path))
                    if listed.count == 1, let only = listed.first,
                       only.name == (path as NSString).lastPathComponent,
                       !only.isDirectory {
                        loadError = .notDirectory(path)
                    } else {
                        entries = listed
                    }
                } catch {
                    // 设备在线但目标目录不可读：保留当前目录与已连接状态，仅提示原因
                    loadError = (error as? ADBError) ?? .underlying(error.localizedDescription)
                }
            } catch let error as ADBError {
                loadError = error
                if case .notInstalled = error { needsGuide = true }
                if case .manualPathInvalid = error { needsGuide = true }
            } catch {
                loadError = (error as? ADBError) ?? .underlying(error.localizedDescription)
            }
            DispatchQueue.main.async {
                guard let self, self.androidToken == token else { return }
                if needsGuide {
                    self.refreshADBInfo()
                    self.deviceStatus = ADB.manualPath == nil ? .adbMissing : .adbPathInvalid
                }
                if let entries {
                    self.androidPath = path
                    self.androidEntries = entries
                    self.androidSelection = []
                    self.androidError = nil
                    UserDefaults.standard.set(path, forKey: "LastAndroidPath")
                } else {
                    self.androidSelection = []
                    self.androidError = loadError
                }
                self.androidLoading = false
            }
        }
    }
}

// MARK: - 设置：adb 路径

/// 设置窗口：按分区组织，新增选项只需加一个 Section 视图并挂到下方 Form。
struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                GeneralSettingsSection(model: model)
                ADBSettingsSection(model: model)
            }
            .formStyle(.grouped)

            Divider()
            ADBSetupDisclosure(expanded: $model.guideExpanded)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        // 收起态也需保证上方 Form 完整显示（约 480pt），否则「手動指定」卡片底部被裁
        .frame(width: 620, height: model.guideExpanded ? 690 : 520)
        .focusEffectDisabled()
        // 语言切换后重建，使本窗口内文案重新取值
        .id(model.languageRevision)
        .onAppear { model.refreshADBInfo() }
    }
}

/// 通用分区。后续主题、语言切换等选项加在这里。
struct GeneralSettingsSection: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Section {
            // 语言：显式列出可选项，切换即时生效
            Picker(selection: $model.language) {
                ForEach(AppLanguage.allCases) { lang in
                    Text(lang.displayName).tag(lang)
                }
            } label: {
                // 地球图标：明示这一行是语言设置
                Label {
                    Text(L.s("settings.language"))
                } icon: {
                    Image(systemName: "globe")
                }
            }
            .pickerStyle(.menu)

            Toggle(isOn: $model.showHiddenFiles) {
                Text(L.s("menu.showHidden"))
            }
            .toggleStyle(.switch)
        } header: {
            Text(L.s("settings.general"))
        }
    }
}

/// adb 分区：路径、版本、来源与手动指定
struct ADBSettingsSection: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Group {
                Section {
                    LabeledContent(L.s("settings.currentPath")) {
                        if let path = model.adbPath {
                            Text(path)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .multilineTextAlignment(.trailing)
                                .lineLimit(3)
                                .truncationMode(.middle)
                                .frame(maxWidth: 400, alignment: .trailing)
                        } else {
                            Text(L.s("settings.notFound")).foregroundStyle(.orange)
                        }
                    }
                    LabeledContent(L.s("settings.version")) {
                        if let v = model.adbVersion {
                            Text(v).textSelection(.enabled)
                        } else if model.adbPath != nil {
                            Text(L.s("status.loading")).foregroundStyle(.secondary)
                        } else {
                            Text("—").foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent(L.s("settings.source")) {
                        Text(model.adbPath == nil
                             ? "—"
                             : (model.adbIsManual ? L.s("settings.manualSection") : L.s("settings.auto")))
                            .foregroundStyle(.secondary)
                    }
                    if let problem = model.adbProblem {
                        Text(L.f(problem.key, problem.path))
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .textSelection(.enabled)
                    }
                } header: {
                    Text("adb")
                }

                Section {
                    HStack(spacing: 8) {
                        TextField(L.s("settings.pathPlaceholder"), text: $model.adbPathInput)
                            .font(.system(.body, design: .monospaced))
                            .onSubmit { model.applyManualADBPath(model.adbPathInput) }
                        Button(L.s("action.choose")) { model.chooseADBExecutable() }
                    }
                    HStack(spacing: 8) {
                        Button(L.s("action.apply")) { model.applyManualADBPath(model.adbPathInput) }
                            .disabled(model.adbValidating
                                      || model.adbPathInput.trimmingCharacters(in: .whitespaces).isEmpty)
                        Button(L.s("settings.auto")) { model.resetADBPathToAuto() }
                            .disabled(!model.adbIsManual && model.adbPathInput.isEmpty)
                        Button(L.s("settings.redetect")) {
                            model.refreshADBInfo()
                            model.refreshAndroid()
                        }
                        if model.adbValidating {
                            ProgressView().controlSize(.mini)
                        }
                        Spacer()
                    }
                    if let msg = model.adbValidationMessage {
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(model.adbValidationOK ? Color.green : Color.orange)
                            .textSelection(.enabled)
                    }
                } header: {
                    Text(L.s("settings.manualSection"))
                }
        }
    }
}

/// 安装与配置引导：下载官方包 / Homebrew / PATH 配置
/// 安装引导（可折叠）。安装 adb 是低频、非必需操作，默认收起为一行 Disclosure；
/// adb 缺失/路径失效时由调用方传入 expanded 绑定自动展开。
struct ADBSetupDisclosure: View {
    @Binding var expanded: Bool
    var compact = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            // 显式左对齐并撑满宽度：DisclosureGroup 默认会把内容居中
            ADBSetupGuideView(compact: true)
                .padding(.top, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            // 只用三角表达展开/收起，不再叠加下载图标（语义重复）
            Text(L.s("guide.title"))
                .font(compact ? .caption : .body)
        }
        .focusable(false)
    }
}

struct ADBSetupGuideView: View {
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            guideRow(
                index: "1",
                title: L.s("guide.step1"),
                detail: L.s("guide.step1Detail")
            ) {
                HStack(spacing: 8) {
                    Button(L.s("guide.downloadMac")) { NSWorkspace.shared.open(ADB.macZipURL) }
                        .controlSize(.small)
                    Button(L.s("guide.downloadPage")) { NSWorkspace.shared.open(ADB.downloadURL) }
                        .controlSize(.small)
                }
            }

            guideRow(
                index: "2",
                title: L.s("guide.step2"),
                detail: nil
            ) {
                commandRow(ADB.brewCommand)
            }

            guideRow(
                index: "3",
                title: L.s("guide.step3"),
                detail: L.s("guide.step3Detail")
            ) {
                commandRow(ADB.pathExportCommand)
            }
        }
    }

    @ViewBuilder
    private func guideRow<Actions: View>(
        index: String, title: String, detail: String?,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(index + ".")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .frame(width: 14, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption)
                if let detail {
                    Text(detail).font(.caption2).foregroundStyle(.secondary)
                }
                actions()
            }
        }
    }

    private func commandRow(_ command: String) -> some View {
        HStack(spacing: 6) {
            Text(command)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.06)))
            Button(L.s("action.copy")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
            }
            .controlSize(.small)
        }
    }
}

// MARK: - 主界面

struct ContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                macPane
                androidPane
            }
            .frame(minHeight: 320)
            TransferPanelView(transfers: model.transfers)
            Divider()
            statusBar
        }
        // 不显示键盘焦点环：避免启动或列表重建后某个按钮被自动圈亮。
        // 仅作用于主窗口内容，弹窗（NSOpenPanel / NSAlert）的输入焦点不受影响。
        .focusEffectDisabled()
        .frame(minWidth: 860, minHeight: 560)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "candybarphone")
                .font(.system(size: 30))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("MacDroid")
                    .font(.title2.bold())
                Text(L.s("app.subtitle"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            // adb 状态胶囊：点击打开路径设置（入口在主界面，不在菜单）
            Button { SettingsWindow.show(model: model) } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(model.adbPillColor)
                        .frame(width: 7, height: 7)
                    Text(model.adbPillText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.quaternary, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help(L.s("adb.settings"))

            HStack(spacing: 6) {
                Circle()
                    .fill(model.deviceStatus.pillColor)
                    .frame(width: 7, height: 7)
                Text(model.deviceStatus.pillText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.quaternary, in: Capsule())

            // 显式设置入口：图标 + 文字按钮（adb 胶囊仍可点击，作为快捷方式保留）
            LabelButton(symbol: "gearshape", title: L.s("settings.title"),
                        action: { SettingsWindow.show(model: model) })
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            if model.macLoading || model.androidLoading {
                ProgressView()
                    .controlSize(.mini)
                Text(L.s("status.loading"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if model.transfers.activeCount > 0 {
                ProgressView()
                    .controlSize(.mini)
                Text(L.f("transfer.runningCountFormat", model.transfers.activeCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(L.s("status.ready"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("v\(appVersion)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    /// `finder` 符号仅较新系统提供；旧系统回退到通用图标，避免显示空白
    private static let finderSymbol: String = {
        NSImage(systemSymbolName: "finder", accessibilityDescription: nil) != nil
            ? "finder" : "macwindow"
    }()

    private var macPane: some View {
        FilePaneView(
            title: "Mac",
            subtitle: "",
            symbol: "desktopcomputer",
            path: model.macPath,
            rootLabel: L.s("breadcrumb.macRoot"),
            rootSymbol: "house",
            rootTarget: FileManager.default.homeDirectoryForCurrentUser.path,
            onNavigate: { model.navigateMac(to: $0) },
            entries: model.macEntries,
            selection: $model.macSelection,
            isLoading: model.macLoading,
            error: model.macError,
            emptyTitle: L.s("pane.emptyDir"),
            emptySubtitle: "",
            canGoUp: parentPath(model.macPath) != nil,
            onRefresh: { model.refreshMac() },
            onGoUp: { model.macGoUp() },
            onOpen: { model.enterMacDirectory($0) },
            onChooseFolder: { model.chooseMacFolder() },
            onSelect: { model.selectMac($0) },
            storage: model.macStorage,
            hiddenFilesToggle: (isOn: model.showHiddenFiles,
                                perform: { model.toggleHiddenFiles() }),
            paneID: "mac",
            showsSetupGuide: false,
            actions: [
                PaneAction(
                    title: L.s("action.upload"), symbol: "arrow.up.doc",
                    isEnabled: !model.macSelection.isEmpty && model.deviceStatus.isConnected,
                    perform: { model.uploadSelection() }),
                PaneAction(
                    title: L.s("action.newFolder"), symbol: "folder.badge.plus",
                    isEnabled: true,
                    perform: { model.createMacFolder() }),
                PaneAction(
                    title: L.s("action.delete"), symbol: "trash",
                    isEnabled: !model.macSelection.isEmpty,
                    perform: { model.deleteMacSelection() }),
                PaneAction(
                    title: L.s("action.showInFinder"), symbol: Self.finderSymbol,
                    isEnabled: true,
                    perform: { model.showMacInFinder() })
            ]
        )
    }

    private var androidPane: some View {
        FilePaneView(
            title: "Android",
            subtitle: "",
            symbol: "candybarphone",
            path: model.androidPath,
            rootLabel: L.s("breadcrumb.androidRoot"),
            rootSymbol: "internaldrive",
            rootTarget: "/sdcard",
            onNavigate: { model.navigateAndroid(to: $0) },
            entries: model.androidEntries,
            selection: $model.androidSelection,
            isLoading: model.androidLoading,
            error: model.androidError,
            emptyTitle: model.deviceStatus.isConnected ? L.s("pane.emptyDir") : L.s("device.disconnected"),
            emptySubtitle: model.deviceStatus.isConnected
                ? ""
                : L.s("pane.connectHint"),
            canGoUp: model.deviceStatus.isConnected && parentPath(model.androidPath) != nil,
            onRefresh: { model.refreshAndroid() },
            onGoUp: { model.androidGoUp() },
            onOpen: { model.enterAndroidDirectory($0) },
            onChooseFolder: nil,
            onSelect: { model.selectAndroid($0) },
            storage: model.androidStorage,
            deviceInfo: model.androidInfo,
            paneID: "android",
            showsSetupGuide: model.deviceStatus.needsSetupGuide,
            guideExpanded: $model.guideExpanded,
            onOpenSettings: { SettingsWindow.show(model: model) },
            actions: [
                PaneAction(
                    title: L.s("action.download"), symbol: "arrow.down.doc",
                    isEnabled: !model.androidSelection.isEmpty && model.deviceStatus.isConnected,
                    perform: { model.downloadSelection() }),
                PaneAction(
                    title: L.s("action.newFolder"), symbol: "folder.badge.plus",
                    isEnabled: model.deviceStatus.isConnected,
                    perform: { model.createAndroidFolder() }),
                PaneAction(
                    title: L.s("action.delete"), symbol: "trash",
                    isEnabled: !model.androidSelection.isEmpty && model.deviceStatus.isConnected,
                    perform: { model.deleteAndroidSelection() })
            ]
        )
    }
}

// MARK: - 文件面板

// MARK: - 图标按钮（常态淡底 / hover 加深 / 按下更深）

/// CLT 工具链无 @State 宏，hover 状态放 ObservableObject
final class HoverState: ObservableObject {
    @Published var hovering = false
}

struct IconButtonStyle: ButtonStyle {
    let hovering: Bool
    var isActive = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(
                !isEnabled ? Color.secondary.opacity(0.4)
                    : (isActive ? Color.accentColor : Color.secondary))
            .frame(width: 22, height: 20)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isActive && isEnabled
                          ? Color.accentColor.opacity(configuration.isPressed ? 0.28 : (hovering ? 0.22 : 0.15))
                          : Color.primary.opacity(
                              !isEnabled ? 0.03 : (configuration.isPressed ? 0.16 : (hovering ? 0.10 : 0.05))))
            )
            .contentShape(RoundedRectangle(cornerRadius: 5))
    }
}

struct IconButton: View {
    let symbol: String
    let help: String
    var isDisabled = false
    var isActive = false
    let action: () -> Void
    @ObservedObject private var hover = HoverState()

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
        }
        .buttonStyle(IconButtonStyle(hovering: hover.hovering, isActive: isActive))
        .disabled(isDisabled)
        .focusable(false)
        .help(help)
        .onHover { hover.hovering = $0 }
    }
}

// MARK: - 路径面包屑

/// 路径的一段：显示名 + 点击后跳转的累计绝对路径
struct PathCrumb: Identifiable {
    let id: String
    let name: String
    let target: String
    let isRoot: Bool
}

/// 把绝对路径拆成可点击的段。
/// - rootTarget 之前的前缀被收敛进首段（Mac 传 home，于是 /Users/xxx 直接显示为「个人目录」，
///   与 Finder / 参考实现一致；设备传 "/" 则逐段展开）。
/// - 首段用 rootLabel + 图标；其余段为真实目录名。
func pathCrumbs(_ path: String, rootLabel: String, rootTarget: String) -> [PathCrumb] {
    let root = rootTarget.hasSuffix("/") && rootTarget.count > 1
        ? String(rootTarget.dropLast()) : rootTarget
    // 路径不在 root 之下（如 Mac 侧浏览 /Users/other 或 /）：
    // 从文件系统根逐段展开，首段用 "/" 而非谎称 Home
    let underRoot = root == "/" || path == root || path.hasPrefix(root + "/")
    let base = underRoot ? root : ""
    let baseName = underRoot ? rootLabel : "/"
    var crumbs: [PathCrumb] = [
        PathCrumb(id: base.isEmpty ? "/" : base, name: baseName,
                  target: base.isEmpty ? "/" : base, isRoot: true)
    ]
    guard path.count > base.count, path.hasPrefix(base) else { return crumbs }
    let rest = String(path.dropFirst(base.count))
    // base 为 "" 或 "/" 时不能再补斜杠，否则拼出 //system
    var acc = base == "/" ? "" : base
    for part in rest.split(separator: "/").map(String.init) {
        acc += "/" + part
        crumbs.append(PathCrumb(id: acc, name: part, target: acc, isRoot: false))
    }
    return crumbs
}

/// 可点击路径面包屑：每段可跳转，末段为当前位置（加重、不可点）。
/// 段过多时中间折叠为「…」菜单，保证首段与当前位置始终可见。
struct BreadcrumbView: View {
    let path: String
    let rootLabel: String
    let rootSymbol: String
    /// 首段代表的绝对路径（Mac=home，设备="/"）
    let rootTarget: String
    let onNavigate: (String) -> Void
    /// 超过该段数就折叠中间部分
    var maxVisible = 4

    var body: some View {
        let crumbs = pathCrumbs(path, rootLabel: rootLabel, rootTarget: rootTarget)
        HStack(spacing: 2) {
            if crumbs.count <= maxVisible {
                ForEach(Array(crumbs.enumerated()), id: \.element.id) { idx, crumb in
                    if idx > 0 { separator }
                    crumbView(crumb, isLast: idx == crumbs.count - 1)
                }
            } else {
                // 首段 + … + 末两段
                crumbView(crumbs[0], isLast: false)
                separator
                Menu {
                    ForEach(crumbs[1..<(crumbs.count - 2)]) { crumb in
                        Button(crumb.name) { onNavigate(crumb.target) }
                    }
                } label: {
                    Text("…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .contentShape(Capsule())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(L.s("breadcrumb.more"))
                separator
                ForEach(Array(crumbs.suffix(2).enumerated()), id: \.element.id) { idx, crumb in
                    if idx > 0 { separator }
                    crumbView(crumb, isLast: idx == 1)
                }
            }
        }
        .lineLimit(1)
    }

    private var separator: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(.tertiary)
    }

    @ViewBuilder
    private func crumbView(_ crumb: PathCrumb, isLast: Bool) -> some View {
        if isLast {
            // 当前位置：加重显示，不可点
            HStack(spacing: 3) {
                if crumb.isRoot { Image(systemName: rootSymbol).font(.caption2) }
                Text(crumb.name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .help(crumb.target)
        } else {
            CrumbButton(crumb: crumb, rootSymbol: rootSymbol, onNavigate: onNavigate)
        }
    }
}

/// 单个可点击面包屑段（hover 胶囊底，与参考实现一致）
struct CrumbButton: View {
    let crumb: PathCrumb
    let rootSymbol: String
    let onNavigate: (String) -> Void
    @ObservedObject private var hover = HoverState()

    var body: some View {
        Button { onNavigate(crumb.target) } label: {
            HStack(spacing: 3) {
                if crumb.isRoot { Image(systemName: rootSymbol).font(.caption2) }
                Text(crumb.name)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.primary.opacity(hover.hovering ? 0.10 : 0)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(crumb.target)
        .onHover { hover.hovering = $0 }
    }
}

/// 图标 + 文字按钮：用于需要被明确识别的入口（如“设置”），
/// 比纯图标按钮更醒目，带 hover / 按下反馈。
struct LabelButtonStyle: ButtonStyle {
    let hovering: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout)
            .foregroundStyle(isEnabled ? Color.primary : Color.secondary.opacity(0.4))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            // 常态与状态胶囊同底（.quaternary），hover / 按下再叠加加深，
            // 确保它看起来是个可点按钮而不是装饰性文字
            .background {
                ZStack {
                    Capsule().fill(.quaternary)
                    if isEnabled && (hovering || configuration.isPressed) {
                        Capsule().fill(Color.primary.opacity(configuration.isPressed ? 0.14 : 0.08))
                    }
                }
            }
            .contentShape(Capsule())
    }
}

struct LabelButton: View {
    let symbol: String
    let title: String
    let action: () -> Void
    @ObservedObject private var hover = HoverState()

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                Text(title)
            }
        }
        .buttonStyle(LabelButtonStyle(hovering: hover.hovering))
        .focusable(false)
        .help(title)
        .onHover { hover.hovering = $0 }
    }
}

// MARK: - 存储容量 / 设备信息条

/// 容量条：细进度条 + 「已用 / 总量 · 可用」文字。
/// 空间紧张（≥90%）时进度条转橙，提示用户注意。
struct StorageBarView: View {
    let storage: StorageInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.10))
                    Capsule()
                        .fill(storage.usedFraction >= 0.9 ? Color.orange : Color.accentColor)
                        .frame(width: max(2, geo.size.width * storage.usedFraction))
                }
            }
            .frame(height: 4)

            HStack(spacing: 4) {
                Text(L.f("storage.usedFormat",
                         storageSizeText(storage.used), storageSizeText(storage.total)))
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(L.f("storage.freeFormat", storageSizeText(storage.available)))
                Spacer(minLength: 0)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
        }
        .help(storage.label ?? "")
    }
}

/// Android 设备概况：型号 · 系统 · 架构 · 电量（字段缺失自动省略）
struct DeviceInfoBarView: View {
    let info: AndroidDeviceInfo

    var body: some View {
        HStack(spacing: 6) {
            if let name = info.nameText {
                chip("candybarphone", name)
            }
            if let sys = info.systemText {
                chip("gearshape", sys)
            }
            if let abi = info.abi {
                chip("cpu", abi)
            }
            if let level = info.batteryLevel {
                chip(batterySymbol(level, charging: info.batteryCharging ?? false),
                     "\(level)%")
            }
            Spacer(minLength: 0)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private func chip(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
            Text(text)
        }
        .fixedSize()
    }

    private func batterySymbol(_ level: Int, charging: Bool) -> String {
        if charging { return "battery.100.bolt" }
        switch level {
        case ..<15: return "battery.0"
        case ..<40: return "battery.25"
        case ..<65: return "battery.50"
        case ..<90: return "battery.75"
        default: return "battery.100"
        }
    }
}

struct PaneAction {
    let title: String
    let symbol: String
    var isEnabled: Bool = false
    var perform: () -> Void = {}
}

struct FilePaneView: View {
    let title: String
    let subtitle: String
    let symbol: String
    /// 完整绝对路径（面包屑据此拆段）
    let path: String
    /// 面包屑首段：显示名与 SF Symbol（Mac=个人目录，Android=内部存储）
    let rootLabel: String
    let rootSymbol: String
    /// 首段代表的绝对路径（Mac=home，设备="/"）
    let rootTarget: String
    /// 点击面包屑某段：跳转到该段的累计绝对路径
    let onNavigate: (String) -> Void
    let entries: [FileEntry]
    @Binding var selection: Set<String>
    let isLoading: Bool
    let error: ADBError?
    let emptyTitle: String
    let emptySubtitle: String
    let canGoUp: Bool
    let onRefresh: () -> Void
    let onGoUp: () -> Void
    let onOpen: (FileEntry) -> Void
    let onChooseFolder: (() -> Void)?
    let onSelect: (FileEntry) -> Void
    /// 存储容量（nil 时不显示容量条）
    var storage: StorageInfo? = nil
    /// 设备概况（仅 Android 栏传入）
    var deviceInfo: AndroidDeviceInfo? = nil
    /// 仅 Mac 栏提供：隐藏文件开关（nil 时不显示）
    var hiddenFilesToggle: (isOn: Bool, perform: () -> Void)? = nil
    /// 行点击监视器的 ID 前缀，避免两栏同名条目互相覆盖
    var paneID = "pane"
    /// adb 缺失/路径无效时，在错误态展示安装引导与设置入口
    var showsSetupGuide = false
    /// 安装引导展开状态（仅 Android 栏传入）
    var guideExpanded: Binding<Bool>? = nil
    var onOpenSettings: (() -> Void)? = nil
    let actions: [PaneAction]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.headline)
                Spacer()
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            HStack(spacing: 6) {
                IconButton(symbol: "arrow.up", help: L.s("tooltip.goUp"),
                           isDisabled: !canGoUp || isLoading, action: onGoUp)

                BreadcrumbView(path: path, rootLabel: rootLabel,
                               rootSymbol: rootSymbol, rootTarget: rootTarget,
                               onNavigate: onNavigate)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let onChooseFolder {
                    IconButton(symbol: "folder.badge.gear", help: L.s("tooltip.chooseFolder"),
                               action: onChooseFolder)
                }
                if let toggle = hiddenFilesToggle {
                    IconButton(symbol: toggle.isOn ? "eye" : "eye.slash",
                               help: toggle.isOn ? L.s("tooltip.hideHidden") : L.s("tooltip.showHidden"),
                               isActive: toggle.isOn,
                               action: toggle.perform)
                }
                IconButton(symbol: "arrow.clockwise", help: L.s("tooltip.refresh"),
                           isDisabled: isLoading, action: onRefresh)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)

            // 表头与数据行共用列宽/间距/内边距，三列均左对齐；
            // 首个等宽占位对应行内图标，使“名称”与文件名起始位置一致
            HStack(spacing: FileListLayout.spacing) {
                Color.clear
                    .frame(width: FileListLayout.iconWidth, height: 1)
                Text(L.s("column.name"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(L.s("column.size"))
                    .frame(width: FileListLayout.sizeWidth, alignment: .leading)
                Text(L.s("column.modified"))
                    .frame(width: FileListLayout.dateWidth, alignment: .leading)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, FileListLayout.hInset)
            .padding(.vertical, 6)
            .background(.bar)

            Divider()

            content

            Divider()

            // 存储容量 / 设备概况（取不到数据时整块不显示，不留空占位）
            if storage != nil || deviceInfo != nil {
                VStack(alignment: .leading, spacing: 5) {
                    if let deviceInfo {
                        DeviceInfoBarView(info: deviceInfo)
                    }
                    if let storage {
                        StorageBarView(storage: storage)
                    }
                }
                .padding(.horizontal, FileListLayout.hInset)
                .padding(.top, 7)
                .padding(.bottom, 2)
            }

            HStack(spacing: 8) {
                ForEach(actions, id: \.title) { action in
                    Button(action: action.perform) {
                        Label(action.title, systemImage: action.symbol)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!action.isEnabled)
                }
                Spacer()
                Text(selection.isEmpty
                     ? L.f("count.itemsFormat", entries.count)
                     : L.f("count.itemsSelectedFormat", entries.count, selection.count))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
        }
        .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && entries.isEmpty {
            VStack(spacing: 10) {
                Spacer()
                ProgressView()
                    .controlSize(.small)
                Text(L.s("status.loading"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 30))
                    .foregroundStyle(.orange)
                Text(error.localizedDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                HStack(spacing: 8) {
                    Button(L.s("action.retry"), action: onRefresh)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    if showsSetupGuide, let onOpenSettings {
                        Button(L.s("adb.settings"), action: onOpenSettings)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    }
                }
                if showsSetupGuide, let guideExpanded {
                    ADBSetupDisclosure(expanded: guideExpanded, compact: true)
                        .padding(.top, 6)
                        .frame(maxWidth: 420, alignment: .leading)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 16)
        } else if entries.isEmpty {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: symbol)
                    .font(.system(size: 34))
                    .foregroundStyle(.tertiary)
                Text(emptyTitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if !emptySubtitle.isEmpty {
                    Text(emptySubtitle)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 16)
        } else {
            // 用 ScrollView + LazyVStack 自绘列表：List 会附加行内缩，
            // 使固定列宽被压缩、列起点与表头错开；自绘可保证逐列精确对齐。
            // LazyVStack 保持懒加载（仅渲染可见行），点击监视器行为不变。
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(entries) { entry in
                        FileRowView(
                            entry: entry,
                            rowID: paneID + "/" + entry.name,
                            onSelect: { onSelect(entry) },
                            onOpen: { onOpen(entry) })
                            .padding(.horizontal, FileListLayout.hInset)
                            .padding(.vertical, 2)
                            .background(
                                selection.contains(entry.name)
                                    ? Color.accentColor.opacity(0.22)
                                    : Color.clear)
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
    }
}

/// 文件列表的列布局常量：表头与数据行共用，保证逐列左对齐
enum FileListLayout {
    /// 行/表头左右内边距（listRowInsets 与表头 padding 必须一致）
    static let hInset: CGFloat = 14
    /// 图标列宽（表头用等宽占位，使“名称”与行内文件名对齐）
    static let iconWidth: CGFloat = 18
    /// 列间距
    static let spacing: CGFloat = 8
    static let sizeWidth: CGFloat = 80
    static let dateWidth: CGFloat = 150
}

/// 行点击：用 NSView 直接接收 mouseDown，命中由 hitTest 决定，
/// 无需任何坐标换算，因此不会选错行；clickCount 区分单击/双击，无手势竞争延迟。
struct RowClickView: NSViewRepresentable {
    let onSingle: () -> Void
    let onDouble: () -> Void

    func makeNSView(context: Context) -> ClickView {
        let v = ClickView()
        v.onSingle = onSingle
        v.onDouble = onDouble
        return v
    }

    func updateNSView(_ nsView: ClickView, context: Context) {
        nsView.onSingle = onSingle
        nsView.onDouble = onDouble
    }

    final class ClickView: NSView {
        var onSingle: () -> Void = {}
        var onDouble: () -> Void = {}

        // hitTest 传入的 point 已是父视图坐标系，直接转自身坐标判定；
        // 不可再 convert(from: superview)，那会转换两次导致永不命中。
        override func hitTest(_ point: NSPoint) -> NSView? {
            bounds.contains(convert(point, from: superview)) ? self : nil
        }

        // 窗口非激活时首次点击即生效（macOS 常规行为）
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            if event.clickCount >= 2 { onDouble() } else { onSingle() }
        }

        // 不拦截右键/滚动，交还给系统
        override func rightMouseDown(with event: NSEvent) { nextResponder?.rightMouseDown(with: event) }
    }
}

struct FileRowView: View {
    let entry: FileEntry
    var rowID: String = ""
    var onSelect: () -> Void = {}
    var onOpen: () -> Void = {}

    var body: some View {
        HStack(spacing: FileListLayout.spacing) {
            Image(systemName: entrySymbol(entry))
                .frame(width: FileListLayout.iconWidth)
                .foregroundStyle(entry.isDirectory ? Color.accentColor : Color.secondary)
            Text(entry.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(entrySizeText(entry))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: FileListLayout.sizeWidth, alignment: .leading)
            Text(entryDateText(entry))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: FileListLayout.dateWidth, alignment: .leading)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        // 每行自己接收点击：命中由 AppKit 的 hitTest 决定，天然精确。
        // 不再用「全局坐标换算 + 遍历 frame 找命中」——那套做法在窗口移动、
        // 滚动、视图重建后容易偏差，表现为选错行/高亮错位。
        .overlay(
            RowClickView(onSingle: onSelect, onDouble: onOpen)
        )
        .help(entry.isDirectory || entry.isSymlink ? L.s("tooltip.open") : entry.name)
    }
}


// MARK: - 传输面板

struct TransferPanelView: View {
    @ObservedObject var transfers: TransferManager

    var body: some View {
        if !transfers.items.isEmpty {
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 8) {
                    Text(L.s("transfer.title"))
                        .font(.caption.bold())
                    if transfers.activeCount > 0 {
                        Text(L.f("count.itemsFormat", transfers.activeCount))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(L.s("action.clear")) { transfers.clearFinished() }
                        .buttonStyle(.borderless)
                        .focusable(false)
                        .font(.caption)
                        .disabled(transfers.items.allSatisfy {
                            $0.state == .queued || $0.state == .running
                        })
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)

                ScrollView {
                    VStack(spacing: 5) {
                        ForEach(transfers.items) { item in
                            TransferRowView(item: item)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
                }
                .frame(maxHeight: 132)
            }
            .background(.bar)
        }
    }
}

struct TransferRowView: View {
    let item: TransferItem

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.direction == .upload ? "arrow.up.circle" : "arrow.down.circle")
                .foregroundStyle(stateColor)
            Text(item.name)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(item.name)
            // 布局优先级：文件名用 Spacer(minLength:) 推开，Group 内的进度条按最小宽度排列，
            // 整行通过 VStack .frame(maxWidth: .infinity) 撑满容器，右侧不再留大片空白。
            Group {
                switch item.state {
                case .queued:
                    Text(L.s("transfer.queued"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .running:
                    if let progress = item.progress {
                        HStack(spacing: 8) {
                            ProgressView(value: progress)
                                .frame(minWidth: 120)
                            Text("\(Int(progress * 100))%")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 40, alignment: .trailing)
                        }
                    } else {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.mini)
                            Text(L.s("transfer.running"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                case .done:
                    Text(item.message ?? L.s("status.done"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                case .failed:
                    Text(item.message ?? L.s("status.failed"))
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 8)
            if item.state == .done {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if item.state == .failed {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.orange)
            }
        }
    }

    private var stateColor: Color {
        switch item.state {
        case .done: return .green
        case .failed: return .orange
        default: return .secondary
        }
    }
}