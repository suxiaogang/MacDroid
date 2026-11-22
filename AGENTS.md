# MacDroid

macOS 下的 Android 设备文件传输工具，借助本机已安装的 ADB 实现 Mac 与 Android 设备之间的文件互传。

## 当前状态（v0.12.2）

- **列表点击改为「每行自收事件」**：废弃「全局坐标换算 + 遍历行 frame 找命中」的监视器方案（`RowClickMonitor` / `HostWindowBinder` / 注册代次已全部移除）。该方案依赖坐标基准、frame 时效与遍历顺序，窗口移动/滚动/视图重建后任一偏差都会选错行或点不动。
  - 现在每行覆盖一个 `RowClickView`（NSView），点击由 AppKit `hitTest` 天然精确命中本行，`mouseDown` 的 `clickCount` 区分单击/双击，**无需任何坐标换算**，结构上不可能选错行。
  - 修饰键（Cmd 加选 / Shift 范围选）在回调里读 `NSEvent.modifierFlags`，行为不变。
  - 验证方式：逐行「点击目标 vs 实际选中文件名」核对——Mac 栏、滚动后、Android 栏、切 3 次语言后、移动窗口后均 100% 命中；多选/范围选/双击进入目录均正确。

- **存储空间展示（两侧）**：面板底部显示容量条 + 「已用 x / 总量 · 可用 y」。已用 ≥90% 时进度条转橙。
  - Mac：`URLResourceValues` 卷容量，可用量优先取 `volumeAvailableCapacityForImportantUsage`（与 Finder「可用」口径一致，计入可清除空间）；导航到其他卷时自动重取。
  - Android：`adb shell df -k`（1K 块，避免 `-h` 舍入）；按 `Use%` 列定位数值，兼容 Filesystem 名含空格导致的列偏移。
- **Android 设备概况**：品牌型号、Android 版本 + API level、CPU 架构、电量（含充电图标）。批量 `getprop` + `dumpsys battery` 单次 adb 往返（约 90ms）；字段缺失自动省略，不同 ROM 兼容。
- 采集时机：连接建立、点刷新、传输完成后均会重取；断开或 adb 不可用时整块隐藏，不留残值与空占位。

- **文件类型图标**：按扩展名映射约 20 类常见格式——图片（含 RAW/AVIF/ICO）、设计源文件（psd/sketch/fig）、视频、音频、字幕（srt/ass/vtt）、压缩包、磁盘镜像（iso/dmg）、安装包（apk/ipa/exe/deb）、办公文档（Word/Excel/PPT/PDF/iWork）、电子书、代码与配置、数据/文本、字体、二进制与库、数据库、证书密钥、邮件、种子与下载中转、网页快捷方式等；冷门扩展统一回退通用文档图标。
  - 目录 / 符号链接优先于扩展名；扩展名大小写不敏感。
  - 图标经 `availableSymbol()` 做运行时可用性检查并缓存，旧系统缺失时回退，避免出现空白图标。
  - 避免使用会随界面语言渲染成文字的符号（如 `textformat` 在日文下显示「書式」且超出列宽），字体改用 `character.textbox`。
  - 冲突扩展名按常见度归类：`.ts` → TypeScript（MPEG-TS 用 `.m2ts/.mts`）、`.key` → Keynote。

- **列对齐**：两栏「名称 / 大小 / 修改日期」表头与数据行统一左对齐、逐列起点对齐。列宽、间距、内边距由 `FileListLayout` 常量集中定义，表头与行共用；列表改用 `ScrollView + LazyVStack` 自绘（`List` 会附加行内缩，导致固定列宽被压缩、列起点与表头错开）。

- **8 种语言**：简体中文 / 繁體中文 / English / 日本語 / 한국어 / Deutsch / Français / Español。设置 ▸ 通用 ▸「语言」行带地球图标，下拉按各自语言自称列出，切换即时生效并持久化。
  - 德 / 法 / 西 / 英含 `.stringsdict` 复数规则（法语 one 含 0，其余 one=1）；中 / 日 / 韩无复数变化。
  - 人工翻译的 `.lproj` 由 `check` 校验完整性，`gen` 只重建基础语言（zh-Hans / en）不覆盖翻译。

- **在 Finder 中显示**（仅 Mac 栏）：有选中项时在 Finder 中定位并高亮这些项（支持多选）；无选中项时打开当前目录本身。已失效路径会提示并自动刷新。

- **国际化（8 语言）**：全部面向用户的文案已抽成字符串表，代码中不再散落中文。
- **语言设置**：设置 ▸ 通用 ▸「语言」下拉，可选「跟随系统 / 简体中文 / English」，**切换即时生效并持久化**（重启保留）。语言名按各自语言自称显示，便于识别。
  - 实现要点：macOS 的 `Bundle.main` 在进程启动后不会因写入 `AppleLanguages` 而改变，因此改为直接加载目标 `.lproj` 子 bundle；格式化时使用**与目标语言匹配的 Locale**，否则 `.stringsdict` 复数规则失效（会出现 “1 items”）。视图通过 `.id(languageRevision)` 强制重建以刷新已渲染文案；AppKit 持有的窗口标题另经通知同步。
  - 字符串表：`Resources/zh-Hans.lproj/Localizable.strings`、`Resources/en.lproj/Localizable.strings`（各 113 键）。
  - 英文复数：`Resources/en.lproj/Localizable.stringsdict`（1 item / 2 items、1 folder / 2 folders）。
  - 代码入口：`L.s("key")` 取文案、`L.f("key", args…)` 填格式符；缺键时界面直接显示 key，便于发现漏翻。
  - 专有名词（Mac / Android / adb）与通用符号（—）不翻译，保留字面量。

### 新增设置项

设置窗口已按分区拆分（`SettingsView` 容器 + 各 Section 视图）：

1. 通用类选项加到 `GeneralSettingsSection`；adb 相关加到 `ADBSettingsSection`；
2. 新增独立分区时，仿照现有 Section 写一个 `View`（内部用 `Section { … } header: { … }`），挂到 `SettingsView` 的 `Form` 里即可；
3. 状态放 `AppModel`（`@Published`），这样设置窗口与主界面自动同步；
4. 文案登记到 `tools/i18n.py` 的 `KEY_MAP` 后 `gen` + `check`。
   注意：**同一中文原文只能登记一个 key**（KEY_MAP 以原文为字典键，重复会静默覆盖），
   同文案请复用已有 key；`check` 会检出重复原文与源码引用了不存在的 key。

### 新增一种语言

0. 在 `AppLanguage` 枚举加一个 case（rawValue = `.lproj` 目录名）并给出 `displayName`（该语言的自称），下拉会自动列出；
1. 复制 `Resources/en.lproj` 为 `Resources/<lang>.lproj`（如 `ja.lproj`），翻译等号右侧的值，**不要改键名**；
2. 若该语言有复数变化，参照 `en.lproj/Localizable.stringsdict` 增补（注意：格式串里的占位必须全部用 `%#@name@`，不可与普通 `%@` 混用）；
3. 无需改 `build.sh`——它自动扫描 `Resources/*.lproj` 并写入 `CFBundleLocalizations`；
4. 校验：`python3 tools/i18n.py check`（检查键完整性、空值、格式符一致性）。

### i18n 工具

```bash
python3 tools/i18n.py extract   # 列出源码中文条目，检查是否有未登记 key
python3 tools/i18n.py gen       # 按映射重新生成各语言字符串表（幂等）
python3 tools/i18n.py check     # 校验键完整性 / 空值 / 格式符一致性
```

### 验证语言切换

```bash
./MacDroid.app/Contents/MacOS/MacDroid -AppleLanguages "(en)"      # 强制英文
./MacDroid.app/Contents/MacOS/MacDroid -AppleLanguages "(zh-Hans)" # 强制中文
```

- **文案精简（为国际化做准备）**：移除开发进度式说明（如“浏览 / 传输 / 新建 / 删除已接入”）与重复副标题；栏标题简化为「Mac」「Android」；空态只保留一行标题；设置窗口去掉两段长说明与结尾长句；错误/校验提示改为短句。设置窗口高度随之收紧，避免大片空白。

- **显式设置入口**：头部最右侧「⚙ 设置」按钮（图标 + 文字，与状态胶囊同底色，hover / 按下加深），点击打开独立「设置」窗口。adb 状态胶囊亦可点击，作为直达 adb 配置的快捷方式。应用菜单不保留任何设置入口（不声明 Settings 场景，菜单自动无“设置…”项）。
- **设置窗口分区**：「通用」（当前含“显示隐藏项”开关，与主界面眼睛按钮/⌘⇧. 共享同一状态，双向同步）、「adb」、「手动指定」，底部常驻安装引导。主题、语言切换等后续选项加在「通用」分区。
- **主界面 adb 状态胶囊**：位于设备状态胶囊左侧，「已检测到 adb」绿点 / 「未检测到 adb」灰点 / 「adb 路径无效」红点。
- **点选即时响应**：行单击/双击改用应用级原生点击计数（NSEvent.clickCount）派发，单击选中 0ms 延迟、双击进目录约 200ms（含 adb 往返）。旧实现用 SwiftUI 单击+双击手势组合，单击需等双击判定窗口约 350–430ms 才生效，已移除。导航另加 5s 设备解析缓存，避免每次进目录重复 `adb devices`。
- **adb 路径设置**（入口：头部「设置」按钮，或点击 adb 状态胶囊）：
  - 显示当前生效路径、`adb version` 版本号、来源（自动探测 / 手动指定）；
  - 手动指定：输入框或「选择…」文件面板，保存前执行 `adb version` 校验（非 adb 文件、不存在、无执行权限均拒绝且不写入偏好）；
  - 「恢复自动探测」清除手动设置；「重新检测」重新解析并刷新设备；
  - 自动探测顺序：Homebrew、`/usr/local/bin`、`/usr/bin`、Android SDK platform-tools、`/opt/android-sdk`、`~/platform-tools`，以及 PATH 中的目录。
- **未安装 / 未检测到 adb 的引导（可折叠）**：三步引导（下载官方 Mac 包 / 官方下载页、Homebrew 命令、PATH 配置，命令可一键复制）收在 Disclosure 组件里——安装 adb 属低频非必需操作，**默认收起**为一行「安装 adb」，设置窗口高度随之收紧。
  - **adb 缺失 / 路径失效时自动展开**（联动写在 `deviceStatus.didSet`，覆盖启动与刷新等所有路径），恢复正常后自动收起；
  - Android 栏错误态与设置窗口共享同一展开状态，并提供「adb 路径设置…」直达入口。Mac 侧功能完全不受影响。
- **手动路径失效**不静默回退：状态胶囊显示「adb 路径无效」，并说明具体原因（文件不存在 / 无执行权限）。

- **双向真实传输**：Mac→设备 `adb push`、设备→Mac `adb pull`，支持文件与目录（含中文/空格/单引号文件名、嵌套子目录）。
- **新建文件夹（两侧）**：弹窗输入名称；校验非空、不含 `/`、不为 `.`/`..`、不与现有条目重名（校验失败保留输入重新弹窗）；Mac 用 FileManager，设备用 `adb shell mkdir`（同名报错而非静默成功）。
- **删除（两侧，二次确认）**：
  - Mac：移到**废纸篓**（可恢复），确认文案注明可在废纸篓中恢复；
  - Android：`adb shell rm -rf` **永久删除**，critical 级确认弹窗，明确“设备上没有废纸篓，删除后不可恢复”；目录连同内容删除，符号链接只删链接本身；
  - 确认文案列出条目数、文件夹数量警告与名称清单（超过 8 项折叠为“等”）；取消不产生任何操作。
- **Mac 隐藏文件开关**：Mac 栏路径行的眼睛图标按钮切换（激活时蓝色底），也可用「显示」菜单项或 ⌘⇧. 快捷键；默认关闭，选择持久化。过滤口径与 Finder 一致：点开头（`.gradle` 等）+ 带 `hidden` 标记（`~/Library` 等）。
- **选择**：单击单选、Cmd 加选/减选、Shift 范围选、双击进入目录；选中高亮 + “N 项 · 已选 M”。
- **传输队列面板**：串行执行；实时进度条（轮询目标端已写入大小 ÷ 源总大小，目录递归求和）；完成绿勾 + adb 摘要，失败橙叉 + 原因；“清除已完成”。
- **同名覆盖确认**（传输时）：覆盖并继续 / 取消。
- **完成/新建/删除后自动刷新**对应面板；**目录记忆**重启恢复两侧路径。
- **浏览**：Mac 用 FileManager；Android 用 `adb shell ls -la`（自动探测 adb 常见安装位置、识别唯一在线设备并显示型号）；子目录/上级/刷新/选择目录；根目录与符号链接目录正确处理。
- 错误态（无设备、未授权、无权限、不存在、adb 缺失/路径无效）显示具体原因与重试；设备在线但记忆目录已被删除时，自动回退到 `/sdcard/`，不会卡在坏路径。

## 约束

- 只使用 Xcode Command Line Tools 构建，不依赖完整 Xcode。
- 应用内不集成 adb，使用本机已安装的 adb。

## 构建与运行

```bash
cd MacDroid
./build.sh
open MacDroid.app
```

构建产出 `MacDroid.app`：Universal 二进制（arm64 + x86_64），最低系统 macOS 14.0，ad-hoc 签名。

## 目录结构

```
MacDroid/
├── AGENTS.md            # 项目约定
├── build.sh             # 构建脚本 (swiftc + lipo + 本地化打包 + codesign)
├── icon.icns            # 应用图标（构建时打包为 AppIcon.icns）
├── src/main.swift       # 入口、本地化 L、ADB 桥接、传输引擎与主界面 (SwiftUI)
├── tools/i18n.py        # 字符串表提取 / 生成 / 校验
├── Resources/
│   ├── Info.plist
│   ├── zh-Hans.lproj/Localizable.strings
│   └── en.lproj/
│       ├── Localizable.strings
│       └── Localizable.stringsdict   # 英文复数规则
└── MacDroid.app         # 构建产物
```