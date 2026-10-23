# SevenWork 工作台化改造计划

> 状态：设计定稿，Phase 2 / 3a / 3b / 4 / 5 / 5b / 6 已完成（待人工验收）
> ⚠ 本文的数字类陈述（Service / Feature 计数、目录树）是**当时的快照**，不随代码更新；
> 当前规模看 [`../PROJECT-OVERVIEW.md`](../PROJECT-OVERVIEW.md)，接口契约看 [`../CAPABILITIES.md`](../CAPABILITIES.md)。
> 最后更新：2026-10-19
> 目录现状：运行代码已统一收进 `src/`，根 `SevenWork.ahk` 只是启动器；
> 本文 Phase 0–5 记录里的 `WorkBench/`、`modules/` 路径是当时原貌，当前路径加 `src/` 前缀。
> 目标：把单文件 `SevenWork.ahk` 拆成「平台 + 三个同级模块」，平台管生命周期 / 热键路由 / 帮助，
> 模块各自持有 Service 与 Feature；模块之间零调用，跨模块只走 EventBus。

---

## 0. 命名与目录

| 层级 | 名字 |
| --- | --- |
| 源码根 | **`src/`**（当前运行代码统一收纳） |
| 项目 / 主脚本 | **`SevenWork`** / `SevenWork.ahk` |
| 工作台层 | **`WorkBench/`** |
| 笔记模块 | **`SevenNote`** |
| 外部程序模块 | **`Launcher`** |
| 键位模块 | **`KeysInput`** |

```
SevenWork/
├── SevenWork.ahk              # 组合根：只装配 + 注册模块
├── WorkBench/
│   ├── WorkBench.ahk          # 平台组合根：登记模块 + 初始化协调器
│   ├── Kernel/                # Config / ConfigService / EventBus / State
│   ├── ModuleRegistry.ahk
│   ├── HotkeyRouter.ahk
│   ├── WorkBenchUI.ahk
│   └── Coordinator/PeerCoordinator.ahk
└── modules/
    ├── SevenNote/
    ├── Launcher/
    └── KeysInput/
```

> 改名（脚本名 / `AppName` / AppData / 仓库名）统一放到 Phase 6，不和拆模块同时做。

---

## 1. 模块归属表

| 归属 | 内容 |
| --- | --- |
| `WorkBench/Kernel` | `Config`、`ConfigService`、`EventBus`、`State` |
| `WorkBench` | `ModuleRegistry`、`HotkeyRouter`、`WorkBenchUI`、`PeerCoordinator` |
| `SevenNote` | 7 个 Service + `StatusBar` + 18 个 Feature |
| `Launcher` | `PeerLayoutService`、`PowerShellFeature`、`DeepSeekFeature` |
| `KeysInput` | `CapsLockFeature` |

**SevenNote 的 7 个 Service**：`EditorService`、`ClipboardService`、`NoteStoreService`、
`PandocService`、`ThemeService`、`FontService`、`BackdropService`。

**SevenNote 的 18 个 Feature**：`WindowFeature`、`PasteFeature`、`LineEditFeature`、
`UndoFeature`、`LoadFeature`、`SaveFeature`、`AutoSaveFeature`、`TimestampFeature`、
`SearchFeature`、`StatFeature`、`CaretFeature`、`DateSwitchFeature`、`DateJumpFeature`、
`TitleFeature`、`GoTodayFeature`、`ThemeFeature`、`FontFeature`、`BackdropFeature`。

**平台函数**（当前在顶层，不属任何模块）：

| 现函数 | 去处 |
| --- | --- |
| `HotkeyTable()` / `RegisterHotkeys()` | Phase 5 已拆：平台 → `WorkBench.GetHotkeys()`，模块 → `Module.GetHotkeys()`；`HotkeyRouter.RegisterAll()` 聚合 |
| `ShowHelp()` / `BuildHotkeyHelpText()` | `WorkBench/WorkBenchUI.ahk`（Phase 5 已搬） |
| `ShowStartupTip()` / `EnsureVaultConfigured()` | 平台启动段 |
| `LogError()` / `OnScriptError()` | `WorkBench/Kernel`（日志兜底） |

---

## 2. 启动顺序表

| 序 | 步骤 | 说明 |
| --- | --- | --- |
| 1 | `Config` 静态初始化 | `AppDataDir` / `ConfigPath` / `AppName` |
| 2 | `ConfigService.Init(Config.ConfigPath)` | 清空读缓存、写默认值 |
| 3 | `EnsureVaultConfigured()` + `DirCreate` | 首次运行选笔记目录 |
| 4 | `WorkBench.Init()` | 注册 Kernel、创建 Registry / Router / UI 占位 |
| 5 | `ModuleRegistry.Register(SevenNote, Launcher, KeysInput)` | 只登记，不初始化 |
| 6 | `SevenNoteModule.Init()` | GUI、`State.Set*`、`StatusBar`、18 个 Feature |
| 7 | `LauncherModule.Init()` | 初始化 PowerShell / DeepSeek Feature；热键由 `GetHotkeys()` 交给 Router |
| 8 | `KeysInputModule.Init()` | CapsLock 状态 |
| 9 | `HotkeyRouter.RegisterAll()` | 平台 `WorkBench.GetHotkeys()` + 各模块 `GetHotkeys()` |
| 10 | `LoadFeature.Load()` + 主题 / 字体 / CapsLock 配置 | 恢复上次状态 |
| 11 | `ShowStartupTip()` | 启动提示 |

**模块内部顺序**：`SevenNoteModule.Init()` 里先 `WindowFeature.Init()`（它订阅伙伴窗口事件），
再 `StatusBar.Init()`、`SearchFeature.Init()`、其余 Feature；最后 `BackdropFeature.Init(g)`。
`LauncherModule.Init()` 必须在 `SevenNoteModule.Init()` 之后，确保伙伴窗口出现时笔记窗口已就绪。

> 当前组合根（`SevenWork.ahk` 末尾的装配 + 启动段）就是这张表的基线；Phase 2 只搬位置，不改先后。

---

## 3. 热键归属表

| 模块 | `ctx` | 热键 | 注册方式 |
| --- | --- | --- | --- |
| `WorkBench` | global | `Alt+H` 平台帮助 | 静态 |
| `WorkBench` | 帮助窗口 | `Esc` 关闭帮助 | `WorkBenchUI` 自注册 |
| `WorkBench` | global | `Alt+Shift+Z` 保存并退出 | 静态（广播 `Save.Requested` + `ExitApp`） |
| `SevenNote` | global | `Alt+Z` 呼出 / 隐藏 | 静态 |
| `SevenNote` | global | `Alt+T` / `Shift+Alt+T` / `Alt+=` / `Alt+-` | 静态 |
| `SevenNote` | editor / search | `Ctrl+F`；`Enter` / `Shift+Enter` / `Esc` | 静态 |
| `SevenNote` | editor | `Ctrl+S`、`Ctrl+Z`、`Ctrl+Shift+Z`、`Ctrl+Y`、`Ctrl+D`、`Ctrl+Shift+↑↓`、`Tab`、`Shift+Tab`、`Ctrl+Shift+V` | 静态 |
| `SevenNote` | global / editor | `Alt+↑↓`、`Alt+Home`、`Ctrl+G`、`Ctrl+Shift+T` | 静态 |
| `SevenNote` | editor | `Ctrl+T`、`Ctrl+H`、`Ctrl+Shift+H` | 静态 |
| `Launcher` | global | `Alt+C` / `Alt+X` 呼出伙伴窗口 | 静态：`LauncherModule.GetHotkeys()` |
| `KeysInput` | global | `Alt+Shift+C` 切换 CapsLock 层 | 静态 |
| `KeysInput` | 全局（层内） | `CapsLock` / `CapsLock+H/J/K/L` | 动态：开关时 `Add` / `Remove` |

约定：

- **静态表** = 模块 `GetHotkeys()` 返回的数组；**动态** = 模块调 `HotkeyRouter.Add/Remove`；
- `ctx` 表达式由模块 `GetContexts()` 提供（`editor` / `search`），Router 只负责 `HotIf`；
- 帮助窗口的 `Esc` 不进模块表，由 `WorkBenchUI` 自己注册与注销；
- 注册顺序仍按 global → editor → search，最后 `HotIf()` 复位。

---

## 4. 模块接口与 Router

```
class SevenNoteModule {
    static Id := "SevenNote"
    static Name := "笔记"
    static Init()
    static GetHotkeys()   ; 数组：{ctx, key, group, line, note?, fn}
    static GetContexts()  ; Map: "editor" / "search" → 表达式
    static GetMetadata()  ; 帮助用：{name, desc, order, hotkeys}
    static Shutdown()
}
```

- AHK 没有接口，`ModuleRegistry` 用 `HasMethod` / `HasProp` 校验必需成员；
- `GetHotkeys()` 里的 `fn` **必须用 lambda 或 `.Bind(类对象)`** —— 探针实测裸引用
  `Probe.Toggle` 会报 `Missing a required parameter`（`this` 丢失）；
- `HotkeyRouter` API：`RegisterAll()`（无参，内部聚合平台 + 模块）、
  `Add(key, fn, ctx)`、`Remove(key)`、`Refresh(module)`、`Reset()`；
- Router 不 import 任何模块内部类；模块只调 Router 的公开 API。

---

## 5. 改造阶段

### Phase 0 · 地基（已完成）

已完成：

- 命名定稿：`SevenWork` / `SevenWork.ahk` / `WorkBench/` / `SevenNote` / `Launcher` / `KeysInput`；
- 删除 `tests/`（提交 `c864226`），端到端测试待重构后按模块接口重建；
- 修正 `.clinerules/04` 关于 auto-execute 的错误表述；
- 四个探针通过：auto-execute 边界、静态方法 `this`、`#Include` 顺序、`Module.Init()` 生命周期；
- 本文档入库；Phase 1 的 `#Include` 清单与文件命名已定稿。

### Phase 1 · 平台骨架（行为不变）

已完成：

- 4 个 Kernel 类搬入 `WorkBench/Kernel/`，主脚本原位置改为 `#Include`（Phase 1 时 4209 行）；
- 新增 `ModuleRegistry` / `HotkeyRouter` / `WorkBenchUI` 占位 / `Coordinator` 占位；
- `HotkeyRouter.RegisterAll(HotkeyTable())` 接管组合根热键注册，逻辑与原 `RegisterHotkeys()` 逐行一致；
- 语法检查（WorkBench 全部文件）与沙箱启动（`#SingleInstance Off`，
  `ShowStartupTip()` → `ExitApp()`）均通过：stderr 为空、`_error.log` 无新增。

待做：

- 人工验收：启动、`Alt+Z`、`Alt+H`、全部热键、保存 / 主题与改造前一致（与 Phase 2 一并做）。

### Phase 2 · SevenNote 模块化（已完成，待人工验收）

已完成：

- 7 个 Service 搬入 `modules/SevenNote/Services/`；`StatusBar` 与 18 个 Feature 搬入
  `modules/SevenNote/`，主脚本原位改为 `#Include`（Phase 2 完成时 1363 行；Phase 3b 后约 620 行）；
- `SevenNoteModule.Init()` 接管 GUI 创建、`OnSize`、Feature 挂载；`Start()` 负责启动恢复；
- `OnSize` 改为经 `State.GetXxx()` / `GuiCtrlFromHwnd(State.GetEd())` 取控件；
  `search*` 由 `SearchFeature.Layout()` 管理；
- `HotkeyRouter.RegisterAll(table, SevenNoteModule.GetContexts())`；
  Router 不再直接引用 `SearchFeature`；
- `docs/legacy/SevenNote.v2.4.3.ahk` 保留拆分前完整快照（用户要求保留源码），不参与运行；
- 验证：沙箱完整 `Init()` + `Show()`、stderr 为空、`_error.log` 无新增；
  `.ahk` 无 BOM 且全 CRLF。

待做：

- 人工验收（需关闭现有实例）：笔记全部功能 + 主题 / 背景图 / 搜索 / 日期 / 标签 /
  图片 / 自动保存；窗口拉伸时文字不闪；
- `GetHotkeys()` 曾暂缓到 Phase 5：当时 SevenNote 的热键仍在组合根 `HotkeyTable()`，
  Launcher 在 Phase 3a、KeysInput 在 Phase 4 先改用 `GetHotkeys()`；Phase 5 已把
  SevenNote 的 27 条热键搬入 `SevenNoteModule.GetHotkeys()`，组合根不再持有热键表。

### Phase 3 · Launcher 模块化（3a / 3b 已完成，待人工验收）

已完成（3a）：

- `PeerLayoutService` 搬入 `modules/Launcher/Services/`；
  `PowerShellFeature` / `DeepSeekFeature` 搬入 `modules/Launcher/Features/`，
  主脚本原位改为 `#Include`；
- 新增 `modules/Launcher/LauncherModule.ahk`：`Init()` 持有两个 Feature 的生命周期，
  `GetHotkeys()` 声明 `Alt+C` / `Alt+X`；
- 两个 Feature 的 `Init()` 不再自注册热键；组合根 `HotkeyTable()` 并入
  `LauncherModule.GetHotkeys()`，仍由 `HotkeyRouter` 统一注册，帮助文本同源；
- `SevenNoteModule.Init()` 不再调用 Launcher 的 Feature。

已完成（3b）：

- 新增 `WorkBench/WorkBench.ahk`：`Init()` 登记 SevenNote / Launcher 两个模块，
  并初始化 `PeerCoordinator`；
- 堆叠算式（方案一 / 方案二、DWM 不可见边框、最小尺寸）从
  `WindowFeature._StackWithPeer()` 上收到 `PeerCoordinator.PlanStack()`；
  `WindowFeature` 只保留 `_docked` / `_stacked` / 底稿状态与窗口应用；
- `PowerShellFeature` / `DeepSeekFeature` 落位后广播 `Launcher.Opened`；
  `WindowFeature.Show()` 末尾广播 `SevenNote.WindowReady`，协调器记录双方最近落位；
- 真实布局时由协调器广播 `SevenNote.Move` / `Launcher.Move`（载荷为物理外框）；
- 旧 `Peer.Preparing` / `Peer.Placed` / `Peer.Failed` 与让位 / 冻结状态机在 3b 保持原样；
  Phase 5b 已替换为 `Launcher.*` 生命周期 + Move 事件（见下）。

待做：

- 人工验收：终端 / 浏览器呼出 / 隐藏 / 切换、笔记让位、重启认回窗口。

### Phase 4 · KeysInput 模块化（已完成，待人工验收）

已完成：

- `CapsLockFeature` 搬入 `modules/KeysInput/Features/`，主脚本原位改为 `#Include`；
- 新增 `modules/KeysInput/KeysInputModule.ahk`：`Init()` / `Start()` / `GetHotkeys()`，
  `Alt+Shift+C` 从组合根热键表移入模块；
- `HotkeyRouter` 增加动态 API `Add` / `Remove` / `Reset`，并保存 `contexts`；
  `CapsLock` 与 `H/J/K/L` 开关时经 Router 加 / 卸，不再在 Feature 里裸调 `Hotkey()`；
- `CapsLockMap` 的启动恢复从 `SevenNoteModule.Start()` 移到 `KeysInputModule.Start()`；
- 热键表仍是一份数据：`BuildHotkeyHelpText()` 通过模块 `GetHotkeys()` 看到
  `Alt+Shift+C`，帮助顺序保持 CapsLock → Alt+C / Alt+X；
- 验证：真机启动 stderr 为空、`_error.log` 无新增；
  启动探针 `modules=3 hotkeys=32 helpCaps=254`；
  动态热键探针 `dyn-add=1 / dyn-remove=0`、`caps-base=0 / caps-on=5 / caps-off=0 / reset=0`。

待做：

- 人工验收：`Alt+Shift+C` 开关、`CapsLock+H/J/K/L` 方向键、关层后无残留热键；
  ⚠ 计划原先写的「`Esc` 退出」在旧 `CapsLockFeature` 中没有对应热键，本次按原行为
  未新增，需用户确认是否要补；**上下文热键无法用 `Send` 触发**，只能人工按键。

### Phase 5 · WorkBenchUI 统一帮助（已完成，待人工验收）

已完成：

- `ShowHelp()` / `BuildHotkeyHelpText()` 从主脚本搬入 `WorkBench/WorkBenchUI.ahk`；
- `WorkBenchUI` 遍历 `ModuleRegistry.All()` 的 `GetMetadata()` 聚合帮助；没有
  `GetMetadata()` 的模块退回 `GetHotkeys()`，新模块的组名自动追加，不必改显示函数；
- 平台热键（`Alt+H` / `Alt+Shift+Z`）归 `WorkBench.GetHotkeys()`，帮助里单独一组
  `【平台】`；`Alt+Shift+Z` 只广播 `Save.Requested`，不直接调用模块内部 Feature；
- SevenNote 的 27 条热键从组合根搬入 `SevenNoteModule.GetHotkeys()`；Launcher /
  KeysInput 补 `GetMetadata()`，`order` 保持「CapsLock → Alt+C / Alt+X」的旧顺序；
- `HotkeyRouter.RegisterAll()` 改为无参：平台 + 各模块 `GetHotkeys()`，上下文从
  各模块 `GetContexts()` 聚合；同一 `ctx + key` 去重（平台优先）；
- 帮助窗口 `Esc` 由 `WorkBenchUI` 自注册 / 注销，标题栏关闭与 `Esc` 两条路径都清理；
- 验证：真机启动 stderr 为空、`Alt+Z` 可呼出；帮助 9 组 / 32 条；
  探针 `platform=2 seven=27 launcher=2 keys=1 saveHandlers=1`；
  `Alt+H` 打开、`Esc` 关闭、标题栏关闭后重开均正常。

代价 / 风险：

- 上下文热键与帮助窗口 `Esc` 的完整交互仍须人工按键验收（`Send` 只能覆盖全局热键）；
- `Alt+Shift+Z` 现在经 `Save.Requested` 间接触发保存，需人工确认「保存并退出」；
- 本轮没有新增「CapsLock 层 `Esc` 退出」热键，旧行为未变。

### Phase 5b · Move 事件接管窗口（已完成，待人工验收）

已完成：

- `PeerCoordinator._PublishMoves()` 改为真正的执行路径：先广播
  `Launcher.Move`（伙伴下移），再广播 `SevenNote.Move`（笔记堆叠）；
- `WindowFeature` 订阅 `SevenNote.Move` → `_OnNoteMove()`，用物理外框直接
  `WinMove`；`_StackWithPeer()` 不再直接搬笔记或伙伴窗口，只更新
  `_stacked` / `_peerRect` 状态；
- `LauncherModule` 订阅 `Launcher.Move` → `_OnMove()`，统一搬终端 / 浏览器；
- 生命周期事件改为 `Launcher.Preparing` / `Launcher.Opened` / `Launcher.Failed`，
  删除 `Peer.Preparing` / `Peer.Placed` / `Peer.Failed` 三条旧桥接；
- `Launcher.Opened` 仍由两个 Launcher Feature 落位后广播，`WindowFeature` 与
  `PeerCoordinator` 同时订阅（前者适配、后者记录）。

代价 / 风险：

- 窗口执行路径从「`WindowFeature` 直接调用」改为「事件订阅」，行为等价但必须
  真机验收 `Alt+C` / `Alt+X` 的呼出 / 隐藏 / 切换与笔记让位；
- `Launcher.Move` 由模块级处理，`LauncherModule.Init()` 增加了只注册一次的守卫；
- 移动事件是同步的，保持旧顺序（先伙伴、后笔记）；异步时序不变。

### Phase 6 · 改名（已完成，待人工验收）

已完成：

- 根启动器与组合根改名为 `SevenWork.ahk` / `src/SevenWork.ahk`，根启动器只
  `#Include src\SevenWork.ahk`；
- `Config.AppName`、`AppDataDir` / `ConfigPath` / `PandocPath`、日志兜底路径全部改为
  `SevenWork` / `SevenWork-Dev` / `SevenWork\pandoc.exe`；
- 新增 `MigrateLegacyAppData()`：首次升级时复制 `_config.ini`、`_deepseek-profile`、
  `_deepseek.mode` 与旧 pandoc；旧 `SevenNote-Dev` 原样保留，不自动删除；
- `PowerShellFeature` 窗口标题改为 `SevenWork PowerShell`，并保留旧
  `SevenNote PowerShell` 的认窗兜底；消息框标题统一用 `Config.AppName`；
- README / `docs/` / `.clinerules` 的路径与产品名同步；GitHub 仓库名 / Release 资产名
  仍需在 GitHub 上手动改。

验证：

- 真实复制 DeepSeek profile **950,623,396 字节**，源 / 目标字节数一致；
- 新入口 `SevenWork.ahk` 编译成功（64 位、PE `0x8664`），启动 6 秒存活且
  `_error.log` 无新增；上下文热键仍须人工按键验收。

代价 / 风险：

- 首次升级启动要复制约 950MB profile，会多花几秒；
- 旧 `SevenNote-Dev` 目录保留，确认新配置可用后再由用户删除；
- GitHub 仓库名、徽章与 Release 链接不会因本地改名自动更新。

---

## 6. 已验证事实与硬约束

| 探针 | 结果 | 对改造的影响 |
| --- | --- | --- |
| auto-execute | 函数定义、类定义、运行时 `Hotkey()` **都不结束**；热键 / 热字符串 / `#HotIf` 指令才结束 | 探针驱动仍插在 `ShowStartupTip()` 之后；Router 的 `HotIf()` 调用不会截断启动 |
| 静态方法 `this` | `Probe.Toggle` 裸引用 → `Missing a required parameter`；lambda / `.Bind()` → `this=yes` | `GetHotkeys()` 的 `fn` 必须 lambda 或 Bind |
| `#Include` 顺序 | 反序（consumer → cfg）仍能解析类静态引用；**顶层语句严格按 include 顺序** | `Config` 仍放最前；不要依赖反序 |
| `Module.Init()` | `Init()` + `GetHotkeys()` 返回 lambda 均正常（`this=yes`） | 生命周期接口可用 |
| `tests/` | 已删除（`c864226`） | E2E 待按模块接口重建 |

硬约束：

1. 不改 Kernel / Service 语义，只搬位置；Kernel 冻结、只加不改。
2. Feature 之间零调用；跨模块通信只走 `EventBus`。
3. 依赖方向 `Feature → Service → Kernel → OS`，严禁反向。
4. **一次只搬一个模块**，每一步都保持单文件可运行、可回退。
5. 改名最后做，不与结构改造同批。
6. 上下文热键只能人工按键验证；探针只证明「注册不抛错」。
