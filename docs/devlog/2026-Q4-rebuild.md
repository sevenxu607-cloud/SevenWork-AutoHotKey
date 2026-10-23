# 开发日志 · 2026-Q4　模块化重构期（10-18 ~ 10-19）

> 从 [`../DEVLOG.md`](../DEVLOG.md) 归档（2026-10-21）。
> 这一段是「单文件 → 平台分层」的重构：Phase 0–6、能力层上收、运行代码收进 `src/`。
> 结论已沉淀进 [`.clinerules/02-architecture.md`](../../.clinerules/02-architecture.md) 与
[`WORKBENCH-PLAN.md`](../archive/WORKBENCH-PLAN.md)；条目里的过程只作追溯用。

### 2026-10-19 23:25　Phase 6：改名 SevenWork 并迁移 AppData

**我说**（原话）
> 开始 Phase 6：配置和 DeepSeek profile 都迁到 SevenWork-Dev（会复制约 950MB）

**意图**
把脚本名、`AppName`、AppData 与文档里的产品名统一成 `SevenWork`；DeepSeek profile 一起迁移，
避免升级后重新登录。

**决定 / 过程**
- 根启动器与组合根改为 `SevenWork.ahk` / `src/SevenWork.ahk`；`Config.AppName`、AppData、
  `PandocPath`、日志兜底路径同步；
- 新增 `MigrateLegacyAppData()`：首次升级复制 `_config.ini`、`_deepseek-profile`、
  `_deepseek.mode` 与旧 pandoc；旧 `SevenNote-Dev` 保留不删；
- 源码运行走 `SevenWork-Dev`，编译版走 `SevenWork`（`A_IsCompiled` 分流）；
- 真实复制 profile **950,623,396 字节**，源 / 目标字节数一致；新入口语法预检 `exit=0`、
  真机启动 6 秒存活、`_error.log` 无新增，`Alt+Z` 窗口标题为 `SevenWork`。

**代价 / 风险**
- 首次升级要复制约 950MB，启动会多花几秒；旧目录需用户确认后再删；
- GitHub 仓库名 / Release 资产名不会自动改；上下文热键仍只能人工验收。

**待办**
- [ ] 人工验收全部热键、`Alt+C` / `Alt+X`、保存与重启后的 DeepSeek 登录
- [ ] GitHub 仓库改名并同步徽章 / Release 链接
- [ ] 确认新配置可用后删除旧 `SevenNote-Dev`

### 2026-10-19 23:05　Phase 5b：Move 事件接管窗口

**我说**
> 开始 Phase 5b：Move 事件接管窗口

**意图**
把窗口执行路径从 `WindowFeature` / Launcher 的直接 `WinMove` 改为平台算几何、模块各自订阅
Move 事件；同时清掉 `Peer.*` 桥接。

**决定 / 过程**
- `PeerCoordinator._PublishMoves()` 成为执行路径：先 `Launcher.Move`（伙伴下移）、后
  `SevenNote.Move`（笔记堆叠）；
- `WindowFeature` 订阅 `SevenNote.Move` → `_OnNoteMove()`；`_StackWithPeer()` 只保留状态与底稿；
- `LauncherModule` 订阅 `Launcher.Move` → `_OnMove()`，统一搬终端 / 浏览器；
- 生命周期改为 `Launcher.Preparing` / `Launcher.Opened` / `Launcher.Failed`，删除
  `Peer.Preparing` / `Peer.Placed` / `Peer.Failed`；
- 验证：真机启动 stderr 为空、`_error.log` 未增长；探针触发两次 `PlanStack(..., true)`，
  计划矩形与实际 `WinGetPos` 逐项相同（笔记 `200,10,800,693` / `200,10,800,1092`，
  伙伴下移 `200,1099`）；生命周期探针 `shown 1 → Preparing 0 → Opened 1 → Failed 1`。

**代价 / 风险**
- 执行路径改为事件订阅，行为等价但需人工验收 `Alt+C` / `Alt+X` 的呼出 / 隐藏 / 切换、
  笔记让位与重启认回；
- `LauncherModule.Init()` 增加只注册一次的守卫；移动事件同步，保持旧顺序。

**待办**
- [ ] 人工验收上述窗口流程
- [ ] 推送提交 / 新入口编译验证

### 2026-10-19 21:43　把运行代码统一收进 src/

**我说**（原话）
> 能将现在项目代码统一在一个文件夹收纳吗

**意图**
把散在根目录 / `WorkBench/` / `modules/` 的运行代码收进同一个源码目录，根目录只留双击入口。

**决定 / 过程**
- 选 `src/` + 根启动器：`SevenNote.ahk`、`WorkBench/`、`modules/` 全部 `git mv` 进 `src/`；
- 根 `SevenNote.ahk` 改成 9 行启动器，只 `#Include src\SevenNote.ahk`。这样 `A_ScriptDir`
  仍是项目根，正常启动的 `.logs\`、文档与工具路径都不变；
- `src/SevenNote.ahk` 里的 `#Include` 保持 `WorkBench\...` / `modules\...` 相对路径
  （AHK 按当前文件所在目录解析；临时探针已确认嵌套 include 可用）；
- 同步更新 README、`PROJECT-OVERVIEW` / `PROJECT-IMPLEMENTATION`、`WORKBENCH-PLAN`
  目录说明、`legacy/README`、`.clinerules` 路径与 `.vscode` 的 `maxScanDepth`。

**代价 / 风险**
- 根目录仍有一个 `SevenNote.ahk`（启动器），不是「根目录完全无代码」；
- 直接运行 `src/SevenNote.ahk` 或把探针放在 `src/` 时，开发版日志落 `src/.logs/`；
  正常双击根启动器仍落项目根 `.logs/`，两种入口不要混看日志；
- 历史 DEVLOG / WORKBENCH-PLAN 旧路径不改写，只在计划顶部加目录现状说明。

**待办**
- [x] 启动器 + `src/` 结构启动验证（stderr 空）
- [x] `Alt+Z` 呼出、`Alt+H` 打开 / `Esc` 关闭
- [ ] 编译流程用新入口再跑一次（右键 `SevenNote.ahk` Compile Script）
- [ ] 人工验收上下文热键与 `Alt+Shift+Z`

### 2026-10-19 21:29　Phase 5：WorkBenchUI 统一帮助

**我说**（原话）
> 继续

**意图**
按 `WORKBENCH-PLAN.md` 继续推进：把帮助窗口从组合根搬进 `WorkBenchUI`，让平台 / 模块热键各归其位，
为后续新增模块自动出现在帮助里铺路。

**决定 / 过程**
- `ShowHelp()` / `BuildHotkeyHelpText()` 搬入 `WorkBenchUI`；平台热键 `Alt+H` / `Alt+Shift+Z`
  归 `WorkBench.GetHotkeys()`，帮助里单独一组 `【平台】`；
- SevenNote 的 27 条热键搬入 `SevenNoteModule.GetHotkeys()`；Launcher / KeysInput 补
  `GetMetadata()`，`order` 保持 CapsLock → Alt+C / Alt+X；
- `HotkeyRouter.RegisterAll()` 改为无参，聚合平台 + 各模块 `GetHotkeys()` 与 `GetContexts()`；
  同 `ctx + key` 去重，模块误声明平台热键时平台优先；
- 帮助窗口 `Esc` 由 `WorkBenchUI` 自注册 / 注销；标题栏关闭与 Esc 两条路径都清理；
- 验证：stderr 空、`Alt+Z` 可呼出；帮助 9 组 / 32 条；
  `platform=2 seven=27 launcher=2 keys=1 saveHandlers=1`；
  `Alt+H` 打开、Esc 关闭、标题栏关闭后重开正常；
- 首轮用了 v2.0 不存在的 `Array.Sort`，触发一次异常；改成插入排序后复测通过
  （`_error.log` 保留两条测试期记录，不是当前运行错误）。

**代价 / 风险**
- 上下文热键与 `Alt+Shift+Z` 保存退出仍需人工按键验收；
- 帮助 `Esc` 是 UI 自注册的上下文热键，`Send` 只能验证全局热键；
- 计划里 Phase 5 原本还包含 Move 事件接管，已拆成 Phase 5b，未在本轮改动窗口行为。

**待办**
- [ ] 人工验收 `Alt+H` / `Alt+Z` / `Alt+Shift+Z`、帮助 `Esc` 与标题栏关闭
- [ ] Phase 5b：Move 事件接管窗口
- [ ] Phase 6：改名

### 2026-10-19 21:09　Phase 4：KeysInput 模块化

**我说**（原话）
> 继续

**意图**
推进 Phase 4：把 CapsLock 层从主脚本搬入 `modules/KeysInput/`，动态热键统一走 `HotkeyRouter`。

**决定 / 过程**
- `CapsLockFeature` → `modules/KeysInput/Features/`；新增 `KeysInputModule`
  （`Init` / `Start` / `GetHotkeys`），`Alt+Shift+C` 从组合根表移入模块；
- `HotkeyRouter` 增加 `Add` / `Remove` / `Reset` 与 `_contexts`；CapsLock 与 HJKL
  开关时动态加 / 卸，Feature 内不再裸调 `Hotkey()`；
- `CapsLockMap` 恢复从 `SevenNoteModule.Start()` 移到 `KeysInputModule.Start()`；
  启动顺序加入 `KeysInputModule.Init()` / `Start()`；
- 帮助表顺序保持 CapsLock → Alt+C / Alt+X；
- 验证：真机 stderr 为空、`_error.log` 332 字节不变；
  探针 `modules=3 hotkeys=32 helpCaps=254`、`dyn-add=1 / dyn-remove=0`、
  `caps-base=0 / caps-on=5 / caps-off=0 / reset=0`。

**代价 / 风险**
- 动态 API 只验证到「注册 / 注销不抛错」，`Alt+Shift+C`、CapsLock + HJKL 的真实按键
  仍须人工验收（上下文 / 钩子热键无法用 `Send` 触发）；
- 计划验收项里的「Esc 退出」在旧 `CapsLockFeature` 中也没有对应热键，本次按原行为
  未新增；搜索栏 / 帮助窗口的 `Esc` 不受影响。

**待办**
- [ ] 人工验收 CapsLock 层
- [ ] Phase 5：让 `SevenNote.Move` / `Launcher.Move` 接管窗口

### 2026-10-19 20:55　Phase 3b：堆叠几何上收 PeerCoordinator

**我说**（原话）
> 继续

**意图**
推进 Phase 3b：让 `PeerCoordinator` 成为伙伴窗口布局的平台入口，减少 `WindowFeature`
对具体几何算式的持有，同时保留已验证的 `Peer.*` 行为。

**决定 / 过程**
- 新增 `WorkBench/WorkBench.ahk`，`Init()` 登记 SevenNote / Launcher 并初始化协调器；
- 把 `_StackWithPeer` 的方案一 / 方案二、DWM 不可见边框、最小尺寸算式原样搬进
  `PeerCoordinator.PlanStack()`；`WindowFeature` 只保留 `_docked` / `_stacked` / 底稿状态与窗口应用；
- Feature 落位后新增 `Launcher.Opened`，笔记 `Show()` 末尾新增 `SevenNote.WindowReady`；
  真实布局时协调器广播 `SevenNote.Move` / `Launcher.Move`（物理外框）；
- `Peer.Preparing` / `Peer.Placed` / `Peer.Failed` 与让位 / 冻结状态机不动，避免同批改动窗口行为。

**代价 / 风险**
- `SevenNote.Move` / `Launcher.Move` 目前没有订阅者，Phase 5 才切为执行路径；
  现阶段旧 `Peer.*` 仍是唯一执行路径，新增事件只做状态记录与契约预演；
- 仍需人工验收 `Alt+C` / `Alt+X` 全流程；探针只验证几何与事件顺序。

**待办**
- [ ] 人工验收伙伴窗口呼出 / 隐藏 / 笔记让位 / 重启认回
- [ ] Phase 4 KeysInput；Phase 5 让 Move 接管窗口

### 2026-10-19 23:55　Phase 3a：Launcher 三个类搬出主脚本

**我说**（原话）
> 继续

**意图**
按 Phase 3 把 `PeerLayoutService`、`PowerShellFeature`、`DeepSeekFeature` 收进
`modules/Launcher/`，并让 `Alt+C` / `Alt+X` 由模块声明、Router 统一注册。

**决定 / 过程**
- 按原行范围机械切出三个类，新增 `modules/Launcher/{Services,Features}/`；
  主脚本原位改为 `#Include`，类体逐行比对与 HEAD 只剩「移除自注册热键」一行差异；
- 新建 `LauncherModule.ahk`：`Init()` 调用两个 Feature 的 `Init()`，`GetHotkeys()`
  返回两条全局热键；`SevenNoteModule.Init()` 删掉对 Launcher 的调用；
- `HotkeyTable()` 在末尾并入 `LauncherModule.GetHotkeys()`，注册与 `Alt+H` 帮助
  仍共用一张表；模块热键不再由 Feature 自己 `Hotkey()`。

**代价 / 风险**
- `PeerCoordinator` 仍是占位：现有 `Peer.*` 契约与 `WindowFeature` 让位逻辑原样保留，
  Phase 3b 再接管；这避免在搬类同批改动已验证的窗口行为；
- 主脚本 614 行，仍含 `CapsLockFeature`（Phase 4）与组合根热键表；
- 沙箱已验证 `HotkeyTable()` 共 32 条、`!c` / `!x` 各 1 条、帮助含两行；
  上下文热键与真实呼出只能人工按键验收。

**待办**
- [ ] 关闭现有实例后验收笔记 + `Alt+C` / `Alt+X` / 笔记让位 / 重启认回窗口
- [ ] Phase 3b：`PeerCoordinator` 接管 `Launcher.Opened` / `SevenNote.WindowReady`

### 2026-10-19 23:40　保留源码快照，完成 Phase 2 拆分

**我说**（原话）
> 源码没有问题,重构时可以保留源码,重构新工作

**意图**
确认不必删掉旧单文件；保留一份可对照的源码，同时继续 Phase 2 重构。

**决定 / 过程**
- 新建 `legacy/SevenNote.v2.4.3.ahk`，保存拆分前完整快照，不参与运行；
- 7 个 Service 搬入 `modules/SevenNote/Services/`，`StatusBar` + 18 个 Feature 搬入 `modules/SevenNote/`；
- `SevenNoteModule.Init()` 接管 GUI 创建 / OnSize / Feature 挂载，`Start()` 接管启动恢复；
- `OnSize` 改经 `State.GetXxx()` / `GuiCtrlFromHwnd(State.GetEd())` 取控件；
- Router 改收 `SevenNoteModule.GetContexts()`，不再直接引用 `SearchFeature`；
- 主脚本从 4209 行降到 1363 行。

**代价 / 风险**
- 热键表仍在组合根；`GetHotkeys()` 推迟到 Phase 5；
- Launcher / KeysInput 的类还在主脚本，Phase 3–4 才能完全拆开；
- 沙箱只证明「能初始化、能显示、无异常」，上下文热键与视觉效果仍需人工按键验收。

**待办**
- [ ] 关闭现有实例后启动 `SevenNote.ahk` 人工验收
- [ ] Phase 3：Launcher 模块化

### 2026-10-19 23:10　Phase 1b：热键路由接管

**我说**（原话）
> 继续

**意图**
把组合根的热键注册从主脚本函数抽到 `WorkBench/HotkeyRouter.ahk`，并补齐平台层占位文件。

**决定 / 过程**
- `HotkeyRouter.RegisterAll(table)` 逐行复制原 `RegisterHotkeys()`：global → editor → search，
  同一份 `HotkeyTable()` 驱动注册与帮助；
- 组合根改调 `HotkeyRouter.RegisterAll(HotkeyTable())`，删除原函数；
- 新增 `ModuleRegistry`（登记 / 查找）、`WorkBenchUI` / `PeerCoordinator` 空壳，暂不接入启动流程；
- 验证：WorkBench 全部文件 include `exit=0`、stderr 空；沙箱完整启动（`#SingleInstance Off`，
  `ShowStartupTip()` → `ExitApp()`）stderr 空、`_error.log` 无新增。

**代价 / 风险**
- Router 仍直接引用 `State` / `SearchFeature`，Phase 2 要改为模块 `GetContexts()`；
- 占位类尚未进入组合根，`WorkBench.Init()` 还没建；
- 热键与界面仍需人工按键验收（当前实例在运行，不能直接起第二个）。

**待办**
- [ ] 人工验收 `Alt+Z` / `Alt+H` / 保存 / 主题
- [ ] Phase 2：搬 SevenNote 模块

### 2026-10-19 22:10　Phase 1a：Kernel 搬出主文件

**我说**（原话）
> 继续

**意图**
开始 Phase 1，先把 4 个 Kernel 类从单文件搬进 `WorkBench/Kernel/`，保持行为不变。

**决定 / 过程**
- 按原行范围机械切出 `Config` / `ConfigService` / `EventBus` / `State`，主脚本原位置只留 4 条 `#Include`；
- 清理搬出文件里的 `tests` 过时注释；主脚本架构注释标明 Kernel 实现位置；
- 验证：Kernel 单独 include + 主脚本 include 路径两轮语法检查均 `exit=0`、stderr 空；
  再用 `#SingleInstance Off` 的临时副本把 `ShowStartupTip()` 换成 `ExitApp()` 跑完整组合根，
  stderr 空、`_error.log` 无新增。

**代价 / 风险**
- 未用真机启动主脚本（当前有实例在运行，`#SingleInstance Force` 会杀掉它），热键与界面仍需人工验收；
- 主脚本行号整体前移约 210 行，后续文档里的行号锚点要重算；
- `ModuleRegistry` / `HotkeyRouter` / `WorkBenchUI` / `Coordinator` 仍未建。

**待办**
- [ ] Phase 1b：`HotkeyRouter` 包住 `HotkeyTable()`，注册结果与 HEAD 一致
- [ ] 人工验收 `Alt+Z` / `Alt+H` / 保存 / 主题

### 2026-10-19 21:10　Phase 0 探针与三张表落纸

**我说**（原话）
> 继续

**意图**
按上一轮 Next 完成 Phase 0：把三张归属表写进文档、修正 `.clinerules/04` 的错误表述、
用探针确认 `#Include` 顺序 / 静态方法 `this` / `Module.Init()` 生命周期。

**决定 / 过程**
- 新建 `docs/WORKBENCH-PLAN.md`：模块归属 / 启动顺序 / 热键归属三张表 + 模块接口 + Phase 0–6；
- 修正 `.clinerules/04`：实测函数定义、类定义、运行时 `Hotkey()` **都不结束** auto-execute，
  真正结束它的是热键 / 热字符串 / `#HotIf` 指令；探针驱动仍插在 `ShowStartupTip()` 之后；
- 探针结论：裸 `Class.Method` 丢 `this`（`Missing a required parameter`），lambda / `.Bind()` 正常；
  `#Include` 反序仍能解析类静态引用，但顶层语句严格按 include 顺序。

**代价 / 风险**
- 探针只证明接口可用，不替代真机按键；上下文热键仍需人工验证；
- 未改 `SevenNote.ahk`；Phase 1 的 `#Include` 清单与文件命名仍未定稿。

**待办**
- [ ] Phase 1：新建 `WorkBench/Kernel/`，搬 4 个 Kernel 类，`HotkeyRouter` 先包住现有热键表
- [ ] E2E 待模块接口稳定后重建

### 2026-10-19 20:10　删除端到端测试脚本，重构后重建

**我说**（原话）
> 删除测试脚本,后边新重构项目新建

**意图**
工作台化重构会拆掉单文件，`tests\` 的 6 个 `Replace-ExactlyOnce` 锚点必然失配；
先删掉，等 `modules/` 结构稳定后按模块接口重建。

**决定 / 过程**
- `git rm -r tests`（`run_user_journey_demo.ps1`、`user_journey_driver.ahk`）；
- 移除 README / `PROJECT-OVERVIEW` / `PROJECT-IMPLEMENTATION` / `.clinerules/04` 中
  「测试仍存在」的描述；历史版本记录保留不改；
- 验证手段暂时退化为「探针脚本 + 人工按键」。

**代价 / 风险**
- 失去唯一能跑完整用户旅程的自动化回归；拆模块期间只能靠探针 + 手按；
- 帮助窗口 / 上下文热键的验证仍无法用 `Send` 覆盖（见 `.clinerules/04`）。

**待办**
- [ ] 重构后按 `modules/` 的模块接口重建端到端测试（不要再依赖单文件锚点）

### 2026-10-19 19:06　根目录收纳，为模块化重组做准备

**我说**（原话）
> 先进行设计理解,而不是代码重构,需要对齐开发者思路需求,先将项目文件夹做精简收纳,现在根目录太多文件,只保留源码和必要留下的文件,其他收纳,为重组做准备

**意图**
先把仓库摆整齐再谈拆分：根目录只留源码与必须留根的文件，项目文档统一收进 `docs/`；
这一轮不改 `SevenNote.ahk`，也不动 Feature / Service。

**决定 / 过程**
- `git mv` 三份文档：`DEVLOG.md`、`PROJECT-OVERVIEW.md`、`PROJECT-IMPLEMENTATION.md` → `docs/`，保留历史；
- 留根：`SevenNote.ahk`、`README.md`、`LICENSE`、`.gitattributes`、`.gitignore`、`.vscode/`、`.clinerules/`、`screenshots/`、`tests/`、`tools/`（后三者被文档/规则按相对路径引用）；
- 同步引用：README 顶部索引与仓库表、`.clinerules/06-devlog.md` 的写入路径、两份文档的互链。

**代价 / 风险**
- GitHub 上旧路径的书签会失效，且没有迁移提示；
- 历史条目里「落成 PROJECT-OVERVIEW.md（项目根）」按当时事实保留，不改写；
- 未创建 `platform/` / `modules/` 空目录 —— 等 Phase 1 再建，避免空目录误导。

**待办**
- [ ] 补三张表：模块归属 / 启动顺序 / 热键归属
- [ ] Phase 0：修正 `.clinerules/04` 的 auto-execute 表述、改 demo 锚点、探针验证 `#Include` 与 `mod.Init()`

### 2026-10-18 12:30　要一份「实现了什么」的技术梳理

**我说**（原话）
> 介绍目前项目实现了什么,元描述,比如使用ahk语言设计了一个编辑窗口,实现了终端和浏览器程序的快捷呼出和窗口设计,按照举出例子进行项目梳理

**意图**
不要功能清单（「能做什么」），要**技术清单**（「用什么手段做到了」）——
一条一条能对上代码里的 API / 消息号 / 类名。

**决定**
- 从源码里实际提取 DllCall / SendMessage 常量与 34 个类，按技术块归纳成 15 条；
- 落成 `PROJECT-IMPLEMENTATION.md`（与 `PROJECT-OVERVIEW.md` 并列：一个讲「是什么」，一个讲「怎么做到的」）；
- 在 README 顶部与 OVERVIEW 的仓库表里各挂一处索引。

**代价 / 风险**
消息号与 API 名会随 README 版本升级而漂移 —— 文首已声明「技术事实以 `SevenNote.ahk` 为准」。
与 README 的「技术特色」一节有部分重叠（三个核心决策），但角度不同：那节讲取舍，本文讲手段。

**待办**
- [ ] 若后续大改（如换掉 RichEdit / 引入子类化 WndProc），同步补进第 1 / 5 条

---

### 2026-10-18 12:20　要一份项目全景介绍

**我说**（原话）
> 目前项目总体介绍

**意图**
想要一份能一屏看完的项目说明 —— 不是 README 的逐项手册，而是「这是什么、做到哪了、还欠什么」。

**决定**
- 口头给了一版全景（定位 / 痛点 / 能力 / 数据 / 架构 / 状态 / 仓库 / 取向）；
- 落成 `PROJECT-OVERVIEW.md`（项目根，与 README、DEVLOG 并列）；
- 与 README 分工：README = 完整手册（818 行），OVERVIEW = 一页纸全景（含当前欠账与限制）。

**代价 / 风险**
OVERVIEW 里的行数 / 类数会随时间过时 —— 已在文首标注统计口径，改结构时需顺手更新；
与 README 的特性清单有部分重叠，但详略与用途不同（一页 vs 全册）。

**待办**
- [x] 若认同「一页纸」的价值，可在 README 顶部加一行指向它（已加）

---

### 2026-10-18 12:15　提交进版本库

**我说**（原话）
> commit

**决定**
- 7 个文件**一次提交**：日志落点改造 + 开发日志两件事合并 —— 因为 `README.md` 被两者共用，
  非交互环境不便按 hunk 拆分，拆错的代价高于合并的代价；
- 提交信息 `开发版报错日志改落项目根,并新增开发日志文档`（按 04-workflow：中文短句、不加英文前缀）；
- 中文信息走 `git commit -F` + UTF-8 临时文件，避开 PowerShell 5.1 按 GBK 传参导致的乱码。

**代价 / 风险**
一次提交含两件事，将来想只回退一半需要手工挑文件；可接受（两者无行为耦合）。

**待办**
- [x] 确认工作区干净（`git status` 无输出）

---

### 2026-10-18 12:10　要求把「我的输入与思考」也记下来

**我说**（原话）
> 能不能将我的输入也总结保存到一个文档中,生成类开发日志,方便我每次清晰目前项目进度,待开发项目和方向,主要记录我的输入和思考,将开发进度保留,不一定是代码实现,而是ai每次帮我记录保存,按规则记录?

**意图**
- 现有 `README` 只记代码变更，看不出「我为什么这么决定、下一步想干什么」；
- 希望有一个固定、由 AI 维护的地方，每次打开就能对齐当前状态；
- 重点是**人的思路与方向**，不是实现细节。

**决定**
- 新建项目根 `DEVLOG.md`（本文件）；
- 新建 `.clinerules/06-devlog.md`，把「何时记、记什么、不记什么」固化成规则；
- 与 README 分工：README = 技术版本表，DEVLOG = 意图与决策。

**代价 / 风险**
- 每个 act 会话多一次文件编辑；条目限制在 30 行内以免膨胀；
- AI 不会后台自动运行 —— 「每次」指每次 act 会话结束时；plan 模式纯讨论不写。

**待办**
- [ ] 用一个真实需求验证这条规则确实会被执行

---

### 2026-10-18 12:08　「没见到」—— 确认日志不是启动就建

**我说**（原话）
> 没见到

**意图**
以为 `.logs` 目录应该立刻出现，实际没有 → 怀疑改造没生效。

**澄清**
不是没生效：`.logs` 由 `LogError` **首次被调用时**才 `DirCreate`，干净启动一次都不调用，
所以目录本就不存在。为让用户「看得见」，手动写入一条 `[SELF-CHECK]` 记录（332 字节），
并排查了 VS Code 是否会隐藏该目录 —— `.vscode/settings.json` 里没有任何 `files.exclude`，
`.logs` 只是因 `.gitignore` 而显示为灰色。

**代价 / 风险**
`.logs` 里会出现一条**非异常**的人工记录；已在该文件内注明「SELF-CHECK，可随时删除」，
不影响「有 `文件` / `行` / `调用栈` 三段才是真异常」的判定。

**待办**
- [x] 确认目录与文件确实存在（`Test-Path` 均为 `True`）

---

### 2026-10-18 12:06　报错日志改落项目根（已用真实异常验证）

**我说**（原话）
> 项目报错日志是否直接建在项目中,方便管理,这里是开发版本
>
> 2

**意图**
开发版排查时不想每次都去 `%AppData%` 翻，希望日志跟着仓库走。

**决定**
- 开发版 → `<项目根>\.logs\_error.log`；编译版仍回 `%AppData%\SevenNote-Dev\`；
- 项目目录不可写时自动回退 AppData（宁可多写一次，也别把日志丢掉）；
- `.logs/` 进 `.gitignore`；
- 路径用 `Config.LogDir` / `Config.LogPath` 两个简写属性按 `A_IsCompiled` 分流。

**依据**
- 用户先追问「sevennote-dev 里 deepseek 命名的文件有用吗」—— 那些是 `Alt+X` 的 Edge profile
  与状态标记（`_deepseek-profile` / `_deepseek.pid` / `_deepseek.mode`），与报错无关；
- `_error.log` 不存在 = `OnError` 从未触发 = 脚本没有未捕获异常。

**代价 / 风险**
日志不进版本库（有意为之）；`.logs` 只在真出错时出现，平时看不到属正常。

**待办**
- [x] 用 `LogError("PROBE ...")` 真造一次，确认落点（已验证：写入 `<项目根>\.logs\_error.log`）
- [ ] 下次真出错时把日志内容贴回来，确认三段格式（消息 / 文件 / 行 / 调用栈）可读

---

### 2026-10-18 11:32　回退到「修好但不跟手」的中间版　`[追溯整理]`

**我说**（原话）
> 不是有一般中间版,问题修复但是不够流畅的版本,回退到那

**意图**
保留「删末尾空行后画面会跟手」的修复，但不要那个导致滑条异常的版本。

**决定**
重建中间版（当前工作区状态）：
- 保留 `EditorService.SyncScrollAfterShrink()`，**带脱节守卫**；
- 触发方式回到 `StatFeature` 的 **500ms** 定时器；
- 删掉 `ScrollSyncFeature` 类、它的事件订阅与 50ms 轮询，组合根的 `ScrollSyncFeature.Init()` 一并移除；
- 顺带清掉 `EM_SETEVENTMASK`（`0x0445`）相关残留。

**代价 / 风险**
修复有效但**慢半拍**（最多 500ms）。这是有意接受的取舍：**滑条可用优先于跟手速度**。

**待办**
- [ ] 观察 500ms 是否可接受

---

### 2026-10-18 11:10　滑条修复两轮失败与回退　`[追溯整理]`

**我说**（原话）
> 滑条功能失效，经常无法滑动
>
> 运行报错了

**意图**
第一轮要求修「删末尾空行后画面不跟手」（RichEdit 只重算 `SCROLLINFO`、不重算行布局也不重绘）；修完后立刻报滑条失效，随后报运行错误。

**过程**
1. 第一版：内容变短就**无条件** `EM_SETSCROLLPOS` 写回 → 用户正拖滚动条时被弹回，表现为「滑条拖不动」；
2. 第二版：加脱节守卫（`EM_GETSCROLLPOS` 与 `nPos` 相差 ≤2px 就返回）+ 改成 50ms 轮询 → 我这边探针全绿（`DIFF_S1_S2FAST≈0.0989`、`SCROLL_TEST rolled=1`），**真机报错**；
3. 证据链：`STDERR` 空、无 `#32770`、`_error.log` 不存在、进程稳定运行 20 分钟 —— **未能复现**，按要求先回退到 HEAD，再回退到中间版。

**结论**
- 不知道错在哪就不该继续猜；先退回可用状态；
- 回归判据固定下来：**修「跟手」不能以「滑条可拖」为代价**；
- 「探针全绿」不等于「真机没问题」—— 自动化证据与用户实际运行是两条独立的验收线。

**代价 / 风险**
功能缺陷（视口脱节）重新回到代码里，属于有意识的欠账。

**待办**
- [ ] 若再处理，必须先拿到报错原文，并考虑子类化 `WndProc`（不再依赖通知 / 轮询）

---