# 状态卡

> **覆盖式更新**：每次会话结束改这一份，不追加流水、不留历史版本（历史在 Git）。
> 新会话先读这里，再核对代码与 `git log` —— 这张卡是**起点，不是真理**。
>
> 更新于 `2026-10-24`　基线提交 `989a746`（七个核心应用 + 三区域；本轮窗口稳定性修复见下）

---

## 当前焦点

七个核心应用与三区域已完成并验证；演示录制链路可自动跑通。
**2026-10-25 起转为 portable 编译分发**：`tools\build.ps1` 已能生成
exe + `web\dist` + `WebView2Loader.dll` 的 staging / ZIP；Pandoc 已从启动
`FileInstall` 降级为 `Alt+M` 的可选 sidecar。
剩**管理页保存手验**、干净机器验收、安装器 / 签名；一键启动 / 自定义布局暂缓。

## 已完成（括号内是验证范围）

### 2026-10-26 应用槽位唤回修复

- **最小化 / 收起的应用能被唤回**：`AppSlotFeature._FindWindow` 改为三级取主窗
  （显示 → 最小化 → 收起），不再把 `IsIconic` / 隐藏的窗口一律跳过。旧逻辑跳过它们
  就找不到窗口 → 走 `Run(cmd)` → 单实例程序（Obsidian）**新开一扇窗**，用户看到的就是
  「不是呼出，而是又多一个进程」。
  （实测：Obsidian 最小化时主窗 `iconic=1`、`WinGetPos` 为 `-21333,-21333,158x26`；
  修复后按 `Alt+Shift+2`，测试窗口 `iconic` 由 1 变 0、进程数不变）
- **恢复最小化后等就绪再落区**：`WinShow` → 若 `IsIconic` 则 `ShowWindow(SW_RESTORE)` →
  轮询到「可见且未最小化」→ `Place`。否则 `PlacementExecutor` 判 `minimized` 直接放弃、
  `ZoneService.Watch` 第一轮复核也会因此停掉。（实测 `ShowWindow` 后约 300ms 才 `iconic=0`）
- 验证范围：AHK 109 + web 17 全绿；类体语法探针通过，造错时 `(182) Missing operand`
  且退出码非 0（反向验证）；真机启动 stderr 空；诊断日志确认 `_FindWindow` 命中最小化
  窗口、`Place ok=1`。**最终落区像素未在用户真实 Obsidian 上复验**（避免反复启动用户程序）。

### 本轮（2026-10-24 区域化）

- **命名统一**：笔记 / 文本 / 文件 / 应用 / 视界 / 按键 / 主题；`Id`、目录与事件名不动。
  （面板探针：7 个应用，顺序符合；底部文案「核心应用」）
- **`ZoneMath`**：三区域纯几何 + 50 条单测（小屏收缩、宽度收缩、副屏偏移、no-fit）。
  （反向验证：改坏 gap → 5 条红、退出码 1；恢复 → 全绿）
- **`ZoneService`**：读 `[Vision]` 配置、算矩形、摆放、注册表、`Center`。
  （探针 2560×1600：记录区 `1773,10,772,564`、辅助区 `1773,580,772,1020`、工作区 `10,10,1757,1590`）
- **笔记落记录区**：`WindowFeature` 重写，删伙伴适配 8 方法 + 4 字段、位置记忆、
  `PeerCoordinator`、`Launcher.*` / `SevenNote.Move` 事件；`State` 去掉隐藏矩形。
  （探针：笔记可见边界 = 记录区；净删约 430 行）
- **应用 / 文件落区**：文件槽位加「打开到」（3 槽 × 2 字段）；终端 / 浏览器落辅助区；
  删 `PeerLayoutService`、`LauncherModule._OnMove`。
  （面板探针：文件 6 字段、默认工作区；README 已同步）
- **应用槽位**：`Alt+Shift+1/2/3`，每槽「命令行 + 区域」，支持任意 exe；`CommandLine.ExeOf`
  解析第一段 + 13 条单测；`Alt+C` / `Alt+X` 保留。
  （面板探针：Launcher 5 条热键、6 字段、默认辅助区）
- **视界模块**：`Alt+Shift+V` 恢复布局（只摆已开窗口），面板说明页（无假字段）。
  （探针：`restore=1/0/0`，笔记摆回记录区）
- **浮层填满辅助区**：提示词库（`WebWindow place:"zone"`）与日期检索（原生控件按区域
  逻辑尺寸排好，再 `Place(fill:true)`）。
  （探针：两者外框 `1764,580,790,1029`、可见 `1773,580,772,1020`；提示词页面
  `512×649`、`__swprompt` 存在、正文 105 字）
- **应用槽位 include 修复**：`CommandLine.ahk` 只进了 tests、没进组合根，按 `Alt+Shift+1`
  报「局部变量未赋值」；补 include 后 `ExeOf("D:\...\Everything.exe") = Everything.exe`。
- **笔记取消置顶**：去掉 `+AlwaysOnTop`。（探针：`WS_EX_TOPMOST=0`）
- **应用 / 文件填满工作区 + 8 秒看管**：Obsidian 外框 `10,10,1757,1590`
  （2/5/9 秒三次一致）；Everything 在辅助区时 `1772,580,774,1021`。
  看管每 500ms 一次，窗口被收起 / 最小化即停；冷启动等待 15 秒。
- **标签窗口**：位置居中记录区（中心与记录区中心一致，外框 `1863,151,592,281`）；
  按钮改 `Text + SS_NOTIFY` 继承主题；点「取消」实测窗口关闭（`after=0`）。
- **按键反馈**：CapsLock 层 Toggle 闪 ToolTip（开启说明 H/J/K/L = 方向键）。
- **清理**：`RectMath.PlanStack/Overlaps/CornerRect`、`Config.StatInterval/DockGap/DockMargin`、
  `ZoneService` 零调用；测试 AHK 133 → 109 条（删掉的是旧伙伴适配用例）。
- **回归**：AHK 109 + web 17 全绿；`check-docs` 退出码 0；真机启动 stderr 空、
  `_error.log` 无新增；`Alt+Z` 笔记仍落记录区。

### 2026-10-24 窗口稳定性修复（本轮）

- **WebWindow 激活容错**：`Activate()` 把 `WinActivate` 失败与 `Resize` / Esc 重注册拆开，
  重新呼出后尺寸和 `Esc` 不再因一次 `Target window not found` 全部跳过。
- **最小化恢复**：WebWindow 重新呼出时用 `ShowWindow(SW_RESTORE)` 恢复，不再依赖
  会按标题匹配失败的 `WinRestore`。
- **笔记窗关闭**：`WindowFeature.Hide()` 返回明确成功/失败；保存失败时给 ToolTip，
  不再静默拒绝关闭；笔记窗移除最大化按钮。
- **日期跳转**：原生对话框移除最大化/最小化；关闭按钮 / Esc / 双击选择统一走
  `CloseDialog()`，先注销上下文热键再销毁；跳转失败保留对话框并给出原因。
- **提示词编辑**：`Hwnd()` 增加 `IsWindow` 校验；打开失败返回 `false`，前端显示错误；
  新建同名提示词改为自动追加 `-2`，不再覆盖已有文件。
- **提示词库关闭**：`WebWindow.Close()` 不再同步 `Eval` 页面复位；页面卡住时不再
  把 Close 线程一起拖住，X / `Alt+P` 都能收起。
- **文件槽位**：先在 `WinHide` 的隐藏态按区域算好并 `WinMove`，再 `WinShow`；
  去掉露面后的 Watch，避免先在工作区闪一下再位移。
- **应用槽位**：`_FindWindow` 只认可见、未最小化、有标题、尺寸正常的窗口；
  不再回退「列表第一个」，也不 `WinShow` 隐藏 / 最小化句柄。Chromium / Electron
  的隐藏合成窗 / 启动画面一旦被强行显示，就是一块没有正常关闭入口的巨大空白窗；
  没有可见主窗时宁可走 `Run(cmd)` 让程序自己唤醒。桌面 / 任务栏类也排除。
- **退出**：`RequestExit()` 用 `finally` 复位 `_exiting`，中途异常不会让
  `Alt+Shift+S` 永久失效。

验证：AHK 109 + web 17 全绿，`check-docs` 通过；真机冒烟（`Alt+S` 开 → 关 → 再开 →
Esc、日期窗开/关、提示词新建/关闭、`Alt+Shift+S` 退出）通过，`_error.log` 无新增。

### 2026-10-24 演示自动化

- 新增 `tools/demo-sevenwork.ps1`、`tools/demo-sevenwork.ahk`、`tools/demo-obs.mjs`
  与 `tools/demo-fixtures/`：临时 Vault + 独立 AHK 驱动 + OBS WebSocket 分章录制。
- `-Mode Test` 13 条断言全绿（面板 / 笔记写入 / `Ctrl+G` / `Ctrl+N` / 文件 /
  Obsidian / 退出）；`-Mode Demo -Record` 产出 7 段 mp4 + 每段 `cover.png`。
- 真实 `%AppData%\SevenWork\_config.ini`、`%AppData%\obsidian\obsidian.json`
  均先备份、结束时还原；录制前用 `Shell.Application.ToggleDesktop()` 收起其它窗口。
- **双显卡前提**：OBS 必须由 Windows 图形设置指定为**省电 / 集显**并重启；
  独显上 `monitor_capture` 会录出黑屏（本机已验证）。
- OBS `StopRecord` 响应早于文件落盘，必须在 `stop` 里等文件大小稳定再搬，
  否则会出现 0KB 片段。
- **亮度对照已实测**：OBS profile `ColorRange=Partial` 的旧视频抽帧平均约 76；
  改 Full 后约 114（`yuvj420p(pc)`）。本地素材建议 Full；浅色壁纸只改注册表
  会被 Windows 自定义主题覆盖，未把系统壁纸改动留在机器上。

### 2026-10-25 portable 编译版

- 新增 `tools/build.ps1`：固定 Ahk2Exe 64 位编译，产出
  `dist\SevenWork\SevenWork.exe`、`web\dist`、`WebView2Loader.dll`、
  许可/构建信息与 portable ZIP。
- Pandoc 降级为可选：删除启动时的 `FileInstall` 与旧 pandoc 迁移复制；
  `Alt+M` 缺失时提示「未检测到 Pandoc」，不再尝试启动 `RunWait`；
  正式包不打包二进制。
- `WebHostService` 编译版显式加载 exe 同级的 `WebView2Loader.dll`；
  启动时增加 WebView2 Runtime 注册表探测，缺失给明确安装提示。
- 实测：编译版 exe 约 1.5MB，staging `web/dist` 约 632KB；启动后
  `Alt+S` 能打开面板、`Alt+Shift+S` 正常退出；AHK 109 + web 17 全绿。
- 仍需：干净机器（无 AHK/Node/Pandoc/WebView2）验收、Inno Setup / 签名、
  运行时缺失时的引导安装、WebView2Loader 的跨机器验证。

### 此前几轮（细节见 `git log`，只留仍需知道的范围）

- Markdown 清洁逻辑独立 + 代码区保护 + 前端测试；面板切页保留未保存值。
- 三份资料拆开；删 `EditorService` 与笔记 `PandocService`；笔记直接写 `.md`。
- 数据安全六项、退出守卫、面板最小化、外观去参数化、字体字号入口恢复。
- 图主题与 `BackdropService` 退场；实验前端移出生产构建。

## 未完成 / 已知风险

| 项 | 状态 |
| --- | --- |
| **一键启动 / 自定义布局** | **暂缓**（用户 2026-10-24 定）。视界页只有说明与恢复布局；布局字段没有消费者就不写，避免假入口 |
| **同区多窗口重叠** | 区域只保证「落到哪块」。终端与浏览器都落辅助区；恢复布局会把它们叠在一起，不做堆叠 |
| **日期选择 / 面板保存未手验** | 演示已验证 `Ctrl+G` 能打开日期框；选中日期后的跳转、管理页保存结果仍需真机确认 |
| **OBS 录制依赖集显** | 本机独显上 `monitor_capture` 黑屏；已在 Windows 图形设置为 OBS 指定省电 / 集显。换机 / 重启后要复查 |
| **应用槽位残留空白窗** | 已修（2026-10-26）：只认「有标题 + 非辅助窗类 + 还原尺寸正常」的句柄，`Chrome_WidgetWin_0` / `Base_PowerMessageWindow` / IME 一律排除；旧实例遗留的空白窗仍需重启对应程序清掉 |
| **辅助区高度 1020** | 未真机验证 Windows Terminal 会不会按 profile 弹回；终端目前只锚定位置、不改高度 |
| **最大化窗口落区** | `PlacementExecutor` 已补 `IsZoomed → ShowWindow(SW_RESTORE)`，**未真机验** |
| **`Alt+Shift+1/2/3`** | 未手按验证输入法 / 驱动是否拦截；`Alt+Shift+V` 同理 |
| **应用槽位认窗** | 按 exe 文件名；取面积最大的主窗；最小化 / 收起的能唤回；多实例仍只取一扇，UWP / `cmd /c start` / 提权窗口不支持 |
| **主脚本 include 完整性** | 单测 include ≠ 生产 include：`CommandLine` 漏过一次；新增能力后要检查 `src\SevenWork.ahk` |
| **提示词白屏** | 已确认页面加载正常（`__swprompt` 存在、正文 105 字）；旧版是 WebView2 子窗口不可见。新代码 `promptVisible=1`，待用户重启目视 |
| **旧配置项** | `[Paths] DeepSeekW/H` 不再读取；`[Folders]` / `[Apps]` 新增 `SlotNZone`，缺省分别工作区 / 辅助区 |
| **笔记字体 / 频闪** | 字重与空行已修；楷体 16pt 是否合意、打字是否还闪仍需目视 |
| **分发未验收** | `web/dist` 入库可用，但运行时打包、跨机器首次运行都没试过 |

## 试过但没通（别重试，除非有新证据）

| 日期 | 试过什么 | 为什么停 |
| --- | --- | --- |
| 2026-10-23 | DWM `SYSTEMBACKDROP` + 拦 `WM_ERASEBKGND` | 同一组合时好时坏，不稳定 |
| 2026-10-23 | `SetWindowCompositionAttribute`（Acrylic） | 窗口整个消失（layered 父窗口裁掉 Chromium 子窗口） |
| 2026-10-24 | 图主题（背景图 + `bgAlpha` 贴图） | 被 WebView2 合成表面整片盖住 |
| 2026-10-24 | 伙伴窗口适配（让位 / 堆叠 / 冻结） | 已由三区域取代，代码删除；不要再引入「谁动谁适配」 |

## 下一步（按顺序，一次做一件事）

1. 重启后手按 `Alt+P` / `Ctrl+G` / `Ctrl+Shift+T`：提示词库与日期框应填满辅助区、
   标签窗居中记录区且内容正常；按 `Alt+1/2/3` 看文件夹是否还漂移。
2. 手按 `Alt+Shift+1`：Obsidian **最小化之后**再按一次，应当被唤回并落工作区
   （不再新开窗口 / 新进程）；再按一次应把它收起。
3. 换小屏 / 换缩放验辅助区高度与最大化窗口落区。
4. 一键启动若要落地，先解决异步启动模型（串行会占住热键线程）。
