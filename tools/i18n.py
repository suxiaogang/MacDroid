#!/usr/bin/env python3
"""从 src/main.swift 提取中文字面量，生成/校验 Localizable.strings。

用法:
  python3 tools/i18n.py extract   # 列出源码中的中文条目与 key 映射
  python3 tools/i18n.py check     # 校验各语言 strings 文件键完整性

key 规则: 语义化短标识（见 KEY_MAP），未登记的条目会报错提示补充。
含插值的条目转换为 printf 格式符（%@ / %lld），由调用处 String(format:) 填充。
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "src" / "main.swift"
RES = ROOT / "Resources"

# 中文原文 -> (key, 英文译文)；含插值者用 %@ / %lld 占位
KEY_MAP = {
    # 通用 / 状态
    "就绪": ("status.ready", "Ready"),
    "读取中…": ("status.loading", "Loading…"),
    "完成": ("status.done", "Done"),
    "失败": ("status.failed", "Failed"),
    "取消": ("action.cancel", "Cancel"),
    "好": ("action.ok", "OK"),
    "重试": ("action.retry", "Retry"),
    "创建": ("action.create", "Create"),
    "应用": ("action.apply", "Apply"),
    "复制": ("action.copy", "Copy"),
    "选择…": ("action.choose", "Choose…"),
    "选择": ("action.select", "Select"),
    "打开": ("action.open", "Open"),
    "清除": ("action.clear", "Clear"),
    "永久删除": ("action.deleteForever", "Delete Permanently"),
    "移到废纸篓": ("action.moveToTrash", "Move to Trash"),
    "覆盖并继续": ("action.overwrite", "Overwrite"),
    # 头部 / 面板
    "Android 设备文件传输": ("app.subtitle", "Android File Transfer"),
    "已检测到 adb": ("adb.detected", "adb Detected"),
    "未检测到 adb": ("adb.missing", "adb Not Found"),
    "adb 路径无效": ("adb.invalidPath", "Invalid adb Path"),
    "adb 路径设置…": ("adb.settings", "adb Settings…"),
    "设置": ("settings.title", "Settings"),
    "通用": ("settings.general", "General"),
    "语言": ("settings.language", "Language"),
    "已用 %@ / %@": ("storage.usedFormat", "%@ of %@ used"),
    "可用 %@": ("storage.freeFormat", "%@ free"),
    "个人目录": ("breadcrumb.macRoot", "Home"),
    "内部存储": ("breadcrumb.androidRoot", "Internal Storage"),
    "更多层级": ("breadcrumb.more", "More levels"),
    "跟随系统": ("language.system", "Follow System"),
    "检测中…": ("device.detecting", "Detecting…"),
    "未连接设备": ("device.disconnected", "No Device"),
    "设备未授权": ("device.unauthorized", "Not Authorized"),
    "检测出错": ("device.error", "Detection Error"),
    "已连接 · %@": ("device.connectedFormat", "Connected · %@"),
    "空目录": ("pane.emptyDir", "Empty Folder"),
    "连接设备并开启 USB 调试": ("pane.connectHint", "Connect a device and enable USB debugging"),
    "名称": ("column.name", "Name"),
    "大小": ("column.size", "Size"),
    "修改日期": ("column.modified", "Modified"),
    "上级目录": ("tooltip.goUp", "Parent Folder"),
    "刷新": ("tooltip.refresh", "Refresh"),
    "选择目录…": ("tooltip.chooseFolder", "Choose Folder…"),
    "选择目录": ("panel.chooseFolder", "Choose Folder"),
    "双击打开": ("tooltip.open", "Double-click to open"),
    "显示隐藏项（⌘⇧.）": ("tooltip.showHidden", "Show Hidden Items (⌘⇧.)"),
    "隐藏隐藏项（⌘⇧.）": ("tooltip.hideHidden", "Hide Hidden Items (⌘⇧.)"),
    "显示隐藏项": ("menu.showHidden", "Show Hidden Items"),
    "隐藏隐藏项": ("menu.hideHidden", "Hide Hidden Items"),
    "%lld 项": ("count.itemsFormat", "%lld items"),
    "%lld 项 · 已选 %lld": ("count.itemsSelectedFormat", "%lld items · %lld selected"),
    # 传输
    "传输": ("transfer.title", "Transfers"),
    "传输中…": ("transfer.running", "Transferring…"),
    "传输中… %lld 项": ("transfer.runningCountFormat", "Transferring… %lld items"),
    "排队中": ("transfer.queued", "Queued"),
    "传输失败": ("transfer.failed", "Transfer failed"),
    "上传到设备": ("action.upload", "Upload"),
    "下载到 Mac": ("action.download", "Download"),
    "新建文件夹": ("action.newFolder", "New Folder"),
    "删除": ("action.delete", "Delete"),
    "在 Finder 中显示": ("action.showInFinder", "Show in Finder"),
    # 新建文件夹弹窗
    "文件夹名称": ("newFolder.prompt", "Folder name"),
    "未命名文件夹": ("newFolder.placeholder", "Untitled Folder"),
    "名称不能为空": ("newFolder.errEmpty", "Name cannot be empty"),
    "名称不能含 /，不能为 . 或 ..": ("newFolder.errInvalid", "Name cannot contain / or be . or .."),
    "已存在同名条目：%@": ("newFolder.errExistsFormat", "Already exists: %@"),
    "无法创建文件夹": ("error.createFolder", "Cannot create folder"),
    "无法创建文件夹：%@": ("error.createFolderPathFormat", "Cannot create folder: %@"),
    # 删除确认
    "移到废纸篓？": ("delete.trashTitle", "Move to Trash?"),
    "永久删除？": ("delete.foreverTitle", "Delete Permanently?"),
    "%lld 个条目": ("delete.itemsFormat", "%lld items"),
    "（含 %lld 个文件夹及内容）": ("delete.foldersFormat", " (including %lld folders and their contents)"),
    " 等": ("delete.etc", " and more"),
    "：\n": ("delete.listSeparator", ":\n"),
    "、": ("delete.nameSeparator", ", "),
    "%@：%@": ("error.itemReasonFormat", "%@: %@"),
    " 等 %lld 项": ("overwrite.moreFormat", " and %lld more"),
    "\n\n可在废纸篓中恢复。": ("delete.trashRecoverable", "\n\nYou can restore from Trash."),
    "\n\n删除后不可恢复。": ("delete.irreversible", "\n\nThis cannot be undone."),
    "部分条目未移入废纸篓": ("delete.partialFail", "Some items were not moved to Trash"),
    "删除失败": ("error.delete", "Delete failed"),
    # 覆盖确认
    "同名条目已存在": ("overwrite.title", "Items Already Exist"),
    "已存在：%@%@。\n继续将覆盖 Mac 上的同名条目。": ("overwrite.macFormat", "Already exists: %@%@.\nContinuing will overwrite the items on your Mac."),
    "已存在：%@%@。\n继续将覆盖设备上的同名条目。": ("overwrite.deviceFormat", "Already exists: %@%@.\nContinuing will overwrite the items on the device."),
    # adb 设置
    "当前路径": ("settings.currentPath", "Current Path"),
    "未找到": ("settings.notFound", "Not Found"),
    "版本": ("settings.version", "Version"),
    "来源": ("settings.source", "Source"),
    "手动指定": ("settings.manualSection", "Manual Path"),
    "自动探测": ("settings.auto", "Auto-detect"),
    "重新检测": ("settings.redetect", "Re-detect"),
    "例如 ~/platform-tools/adb": ("settings.pathPlaceholder", "e.g. ~/platform-tools/adb"),
    "已设置": ("settings.applied", "Applied"),
    "请输入路径": ("settings.errEmptyPath", "Enter a path"),
    "文件不存在：%@": ("settings.errNotExistFormat", "File not found: %@"),
    "无执行权限：%@\n可用 chmod +x 修复": ("settings.errNotExecutableFormat", "Not executable: %@\nFix with chmod +x"),
    "不是有效的 adb：%@": ("settings.errNotADBFormat", "Not a valid adb: %@"),
    "路径不可用：%@": ("settings.errPathUnavailableFormat", "Path unavailable: %@"),
    "（文件不存在）": ("settings.errNotExistSuffix", " (file not found)"),
    "（无执行权限）": ("settings.errNotExecutableSuffix", " (not executable)"),
    "选择 adb 可执行文件": ("settings.chooseADB", "Choose the adb executable"),
    # 安装引导
    "安装 adb": ("guide.title", "Install adb"),
    "下载官方 platform-tools": ("guide.step1", "Download official platform-tools"),
    "解压后在上方选择其中的 adb": ("guide.step1Detail", "Unzip, then select adb above"),
    "下载 Mac 版": ("guide.downloadMac", "Download for Mac"),
    "下载页": ("guide.downloadPage", "Download Page"),
    "或用 Homebrew 安装": ("guide.step2", "Or install with Homebrew"),
    "可选：配置 PATH": ("guide.step3", "Optional: configure PATH"),
    "写入 ~/.zshrc 后重开终端": ("guide.step3Detail", "Add to ~/.zshrc, then reopen Terminal"),
    # 错误
    "未找到 adb，请安装或手动指定路径。": ("error.adbMissing", "adb not found. Install it or set the path manually."),
    "未检测到设备，请连接并开启 USB 调试。": ("error.noDevice", "No device found. Connect one and enable USB debugging."),
    "检测到多台设备，暂不支持切换。": ("error.multipleDevices", "Multiple devices found; switching is not supported yet."),
    "设备 %@：%@，请在设备上授权调试。": ("error.deviceNotReadyFormat", "Device %@: %@. Authorize debugging on the device."),
    "设备不可用": ("error.deviceUnavailable", "Device Unavailable"),
    "请刷新后重试。": ("error.refreshRetry", "Refresh and try again."),
    "请连接设备并开启 USB 调试。": ("error.connectDevice", "Connect a device and enable USB debugging."),
    "不是目录：%@": ("error.notDirectoryFormat", "Not a folder: %@"),
    "无法读取目录：%@": ("error.readDirFormat", "Cannot read folder: %@"),
    "无法打开 Finder": ("error.finderUnavailable", "Cannot Open Finder"),
    "路径已不存在，请刷新后重试。": ("error.pathGone", "The path no longer exists. Refresh and try again."),
    # 关于
    "关于 MacDroid": ("menu.about", "About MacDroid"),
    "借助本机 adb 管理 Android 设备文件。": ("about.detail", "Manage Android files using your local adb."),
    "版本 %@": ("about.versionFormat", "Version %@"),
    # 应用管理（最小可用版）
    "文件": ("pane.filesTab", "Files"),
    "应用程序": ("pane.appsTab", "Apps"),
    "包名": ("apps.packageName", "Package"),
    "类型": ("apps.type", "Type"),
    "操作": ("apps.actions", "Actions"),
    "搜索应用包名…": ("apps.searchPlaceholder", "Search package…"),
    "系统": ("apps.typeSystem", "System"),
    "第三方": ("apps.typeUser", "User"),
    "卸载": ("apps.uninstall", "Uninstall"),
    "系统应用不可卸载": ("apps.systemNoUninstall", "System apps cannot be uninstalled"),
    "无法卸载应用": ("apps.uninstallFailed", "Cannot Uninstall App"),
    "包名：%@": ("apps.packageFormat", "Package: %@"),
    "卸载应用？": ("apps.uninstallTitle", "Uninstall App?"),
    "确定卸载 %@？此操作不可撤销。": ("apps.uninstallConfirmFormat", "Uninstall %@? This cannot be undone."),
    "应用 %lld 个": ("apps.countFormat", "%lld apps"),
    "暂无应用": ("apps.empty", "No Apps"),
    "复制包名": ("apps.copyPackage", "Copy package name"),
    "仅第三方": ("apps.userOnly", "User apps only"),
    "只显示第三方（用户）安装的应用": ("apps.userOnlyHint", "Show only user-installed apps"),
}


def extract():
    """返回 [(行号, 原文)]，仅取代码部分（剔除行注释）。"""
    rows = []
    for i, line in enumerate(SRC.read_text(encoding="utf-8").splitlines(), 1):
        code = line.split("//")[0]
        for m in re.findall(r'"([^"\n]*)"', code):
            if re.search(r"[\u4e00-\u9fa5]", m):
                rows.append((i, m))
    return rows


def to_format(s: str) -> str:
    r"""把 Swift 字面量归一化为 key 映射所用的形态：
    插值 \(...) -> printf 占位符；转义 \n -> 真实换行。"""
    def repl(m):
        expr = m.group(1)
        # 计数类用 %lld，其余字符串用 %@
        if re.search(r"count|Count", expr):
            return "%lld"
        return "%@"
    s = re.sub(r"\\\(([^)]*)\)", repl, s)
    return s.replace("\\n", "\n")


def cmd_extract():
    rows = extract()
    uniq = sorted(set(m for _, m in rows))
    missing = []
    print(f"源码中文条目: 出现 {len(rows)} 处 / 去重 {len(uniq)} 条")
    for s in uniq:
        key_src = to_format(s)
        if key_src not in KEY_MAP:
            missing.append(s)
    if missing:
        print(f"\n未登记 key 的条目 ({len(missing)}):")
        for s in missing:
            print("   ", repr(to_format(s)))
        return 1
    print("全部条目已登记 key ✓")
    return 0


def parse_strings(path: Path):
    keys = {}
    text = path.read_text(encoding="utf-8")
    for m in re.finditer(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;', text, re.M):
        keys[m.group(1)] = m.group(2)
    return keys


def cmd_check():
    expected = {k for k, _ in KEY_MAP.values()}
    ok = True

    # 防线 1：KEY_MAP 以中文原文为字典键，重复文本会被 Python 静默覆盖，
    # 导致先登记的 key 凭空消失（界面显示原始 key）。这里直接扫源码查重。
    tool_src = Path(__file__).read_text(encoding="utf-8")
    seen, dups = {}, []
    for mm in re.finditer(r'^\s*"((?:[^"\\]|\\.)*)":\s*\("([^"]+)"', tool_src, re.M):
        zh, key = mm.group(1), mm.group(2)
        if zh in seen and seen[zh] != key:
            dups.append((zh, seen[zh], key))
        seen[zh] = key
    for zh, k1, k2 in dups:
        print(f"   重复原文（后者覆盖前者）: {zh!r} -> {k1} / {k2}")
        ok = False

    # 防线 2：源码引用的每个 key 必须存在于各语言表中，否则界面会显示原始 key
    src = SRC.read_text(encoding="utf-8")
    used = set(re.findall(r'L\.[sf]\("([^"]+)"', src))
    missing_ref = used - expected
    for k in sorted(missing_ref):
        print(f"   源码引用但表中不存在: {k}")
        ok = False
    unused = expected - used
    for k in sorted(unused):
        print(f"   提示·未被引用的 key: {k}")
    for lproj in sorted(RES.glob("*.lproj")):
        f = lproj / "Localizable.strings"
        if not f.exists():
            print(f"{lproj.name}: 缺少 Localizable.strings")
            ok = False
            continue
        keys = parse_strings(f)
        miss = expected - set(keys)
        extra = set(keys) - expected
        empty = [k for k, v in keys.items() if not v.strip()]
        print(f"{lproj.name}: {len(keys)} 键 | 缺 {len(miss)} | 多 {len(extra)} | 空值 {len(empty)}")
        for k in sorted(miss):
            print("   缺:", k)
        for k in sorted(extra):
            print("   多:", k)
        for k in sorted(empty):
            print("   空:", k)
        if miss or extra or empty:
            ok = False
    # 校验格式符一致性（所有语言对照 zh-Hans）
    zh = parse_strings(RES / "zh-Hans.lproj" / "Localizable.strings")
    for lproj in sorted(RES.glob("*.lproj")):
        if lproj.name == "zh-Hans.lproj":
            continue
        other = parse_strings(lproj / "Localizable.strings")
        for k in sorted(set(zh) & set(other)):
            a = re.findall(r"%(?:lld|@|d)", zh[k])
            b = re.findall(r"%(?:lld|@|d)", other[k])
            if a != b:
                print(f"   格式符不一致 {lproj.name} {k}: zh={a} other={b}")
                ok = False
    print("校验通过 ✓" if ok else "校验失败 ✗")
    return 0 if ok else 1


def esc(s: str) -> str:
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def cmd_gen():
    """重新生成基础语言（zh-Hans / en）字符串表。
    其余语言为人工翻译维护，gen 不覆盖；用 check 校验完整性。"""
    rows = sorted(KEY_MAP.items(), key=lambda kv: kv[1][0])
    for lang, idx in (("zh-Hans", 0), ("en", 1)):
        d = RES / f"{lang}.lproj"
        d.mkdir(parents=True, exist_ok=True)
        lines = [f"/* MacDroid 本地化字符串表 — {lang} */",
                 "/* 由 tools/i18n.py gen 生成，tools/i18n.py check 校验 */",
                 "/* 新增语言：复制本目录为 <lang>.lproj 并翻译等号右侧的值 */", ""]
        for zh, (key, en) in rows:
            lines.append(f'"{key}" = "{esc(zh if idx == 0 else en)}";')
        (d / "Localizable.strings").write_text("\n".join(lines) + "\n", encoding="utf-8")
        print(f"{lang}: {len(rows)} 键")
    return 0


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "extract"
    if cmd == "extract":
        sys.exit(cmd_extract())
    elif cmd == "gen":
        sys.exit(cmd_gen())
    else:
        sys.exit(cmd_check())
