#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent()

; ═══════════════════════════════════════════════════════════════════════════
;  SevenWork —— 版本号以 Config.Version 为准（显示在 Alt+S 面板底部，改这里要一并改它）
;  Windows 本地工作台：WebView2 里的 Milkdown 编辑器 + 若干日常小工具。
;
;  本文件只是**组合根**：首次引导、模块装配、启动提示。
;  分层规则见 .clinerules/02-architecture.md，坑点见 .clinerules/03-ahk-v2.md，
;  方向 / 进度 / 经验见 docs/INTENT.md / STATE.md / EXPERIENCE.md —— 这里不重复。
;
;  ⚠ 未赋值变量（VarUnset）的默认动作改成 OutputDebug：默认的 MsgBox 会**模态卡死**，
;    症状只是「Alt+Z 没反应」，最容易误判成热键没注册。变量名写长一点仍是首选预防。
; ═══════════════════════════════════════════════════════════════════════════
#Warn VarUnset, OutputDebug

; ═══════════════════════════════════════════════════════════════════════════
;  KERNEL 骨架层 —— 实现见 src/WorkBench/Kernel/
; ═══════════════════════════════════════════════════════════════════════════

#Include WorkBench\Kernel\Config.ahk
#Include WorkBench\Kernel\ConfigService.ahk
#Include WorkBench\Kernel\EventBus.ahk
#Include WorkBench\Kernel\State.ahk
#Include WorkBench\ModuleRegistry.ahk
#Include WorkBench\HotkeyRouter.ahk
#Include WorkBench\PanelHostBridge.ahk
#Include WorkBench\WebWindow.ahk
#Include WorkBench\WebPanelUI.ahk

; ═══════════════════════════════════════════════════════════════════════════
;  CAPABILITY 平台能力层 —— 纯平台能力，不认识业务模块
;  只收数字 / hwnd / Gui，返回结构体；不读 Config / State，不发事件。
; ═══════════════════════════════════════════════════════════════════════════

#Include WorkBench\Capabilities\Placement\RectMath.ahk
; ZoneMath：三区域纯几何（记录 / 辅助 / 工作）。只算数字，不碰窗口；
; 由平台服务 ZoneService 调用，模块不直接用它。
#Include WorkBench\Capabilities\Placement\ZoneMath.ahk
#Include WorkBench\Capabilities\Placement\WindowProbe.ahk
#Include WorkBench\Capabilities\Placement\PlacementExecutor.ahk
; UiPaint：Win32 染色原语（标题栏 / 滚动条主题 / ListView 底色）。
; 只收 hwnd + 颜色字符串，不认主题、不读 Config —— 主题是业务策略，在 WorkBench\Services。
#Include WorkBench\Capabilities\Graphics\GlassPaint.ahk
#Include WorkBench\Capabilities\Graphics\UiPaint.ahk
; ExplorerProbe：按**真实路径**找资源管理器窗口（读 Shell.Application.Windows）。
; 不用窗口标题 —— 标题是文件夹名，重名 / 本地化都靠不住。Folders 模块用它做显隐定位。
#Include WorkBench\Capabilities\Shell\ExplorerProbe.ahk
; PandocRunner：用 pandoc 把一个文件转成另一个格式（单文件、通用）。
; pandoc 路径由调用方传入 —— 它不读 Config，与 ExplorerProbe 同一条规矩。
; ⚠ 笔记模块曾有一份专用的 PandocService（RTF → Markdown）。v2.9 起笔记保存不再经过
;   pandoc，那份已随 EditorService 一起删除 —— 现在全项目只有这一处 pandoc 调用点。
#Include WorkBench\Capabilities\Document\PandocRunner.ahk
; DocxHeadingFix：把 .docx 里的自定义标题样式名（「三级标题」「半括号标题（五级）」等）
; 规范成 pandoc 认得的 `heading N` —— 不然整篇会被当成嵌套有序列表、一个标题都出不来。
; 只读源文件，改的是临时副本；tar.exe 缺失 / 解压失败时返回 {ok:false}，调用方转原件。
#Include WorkBench\Capabilities\Document\DocxHeadingFix.ahk
; DocxNumberFix：把 Word 的自动标题编号（「第 1 章 / 1.1 / 1）」）固化成文字。
; 编号不是正文，而是样式 → numbering.xml 的模板 —— pandoc 只取文字，编号整体消失。
#Include WorkBench\Capabilities\Document\DocxNumberFix.ahk
; WebHostService：把 WebView2 挂到任意 hwnd 上，并把目录映射成虚拟主机。
; 笔记编辑区（v2.9 起）就是它 —— Mount / Navigate / Eval / Resize 全在这里。
#Include WorkBench\Capabilities\Web\WebHostService.ahk
; JsText：AHK 字符串 ↔ JS 字面量 / JSON 字符串。WebView2 的 Eval 两头都要它 ——
; 送进去的正文要转义（含 NUL，StrReplace 处理不了），拿回来的结果要反解 JSON 转义。
#Include WorkBench\Capabilities\Web\JsText.ahk

; ═══════════════════════════════════════════════════════════════════════════
;  COORDINATION 跨模块协调 —— 读业务状态、发事件、算几何后交给能力层
; ═══════════════════════════════════════════════════════════════════════════

; PeerCoordinator 已删除（v2.18）：笔记不再按伙伴窗口让位 / 堆叠，改为固定的
; 三区域（ZoneService）。以后若出现新的跨模块布局编排，再在这里恢复协调器。
#Include WorkBench\WorkBench.ahk

; ═══════════════════════════════════════════════════════════════════════════
;  SERVICE 服务层
; ═══════════════════════════════════════════════════════════════════════════

#Include WorkBench\Services\ThemeService.ahk
; ZoneService：三区域（记录 / 辅助 / 工作）的尺寸与摆放。区域住在平台层，
; 因为笔记 / 应用 / 文件都要用，而跨模块零调用 —— Vision 模块只是用户入口。
#Include WorkBench\Services\ZoneService.ahk

; 字号：仍属笔记模块（只影响 RichEdit，而编辑区已交给 WebView2 —— 见 FontService 头注释）
#Include modules\SevenNote\Services\FontService.ahk

; （EditorService 已删除：编辑区交给 WebView2 后它零调用点；
;   IsEmptyNote / EmptyNoteHeader 早已迁到 NoteStoreService。）
#Include modules\SevenNote\Services\NoteStoreService.ahk

; 笔记会话：当前日期 / 实际路径 / 是否已载入，以及 Open / Save 两个动作。
; Feature 之间「先存盘再切走」从此不用互相调用 —— 都问它要结果。
#Include modules\SevenNote\Services\NoteSessionService.ahk

; （PandocService 已删除：笔记保存直接写 .md，不再需要 RTF → Markdown；
;   通用的整文件转换走平台能力 PandocRunner。）
; 粘贴图片落盘（WebView2 → base64 → _assets/<date>/）—— 必须在 NoteStoreService 之后
#Include modules\SevenNote\Services\NoteImageService.ahk

; （PeerLayoutService 已删除：终端与浏览器都改由 ZoneService 落到辅助区，
;   不再需要「同一处右下角」的落点公式。）
; 应用槽位（Alt+Shift+1/2/3）的命令行与区域配置；Feature 在下方 MODULE 区。
#Include modules\Launcher\Services\AppSlotService.ahk

; ═══════════════════════════════════════════════════════════════════════════
;  FEATURE 功能层 —— 用户要做什么
;
;  按用户旅程排序：
;   ① 唤起与关闭    Alt+Z 呼出/隐藏
;   ② 输入与编辑    粘贴 / 行编辑 / 缩进 / 撤销 / 输入增强
;   ③ 保存与持久化  加载 / 保存 / 自动保存 / 时间戳
;   ④ 查看与浏览    搜索 / 字数 / 光标记忆
;   ⑤ 组织与管理    日期切换 / 搜索跳转 / 标签 / 返回当天
;   横切·美观       主题 / 字体 / 字号
; ═══════════════════════════════════════════════════════════════════════════


; ═══════════════════════════════════════════════════════════════════════════
;  ① 唤起与关闭
; ═══════════════════════════════════════════════════════════════════════════

#Include modules\SevenNote\Features\WindowFeature.ahk


; ═══════════════════════════════════════════════════════════════════════════
;  ② 输入与编辑
; ═══════════════════════════════════════════════════════════════════════════

; 撤销 / 行编辑 / 缩进 / 纯文本粘贴：v2.9 起全部移交页面。
; 这些操作都要看光标与选区，前端一套 keymap 天然有上下文；
; AHK 这边从前只能对着 RichEdit 发 SendMessage 猜。


; CapsLockFeature 归 src\modules\KeysInput\（Phase 4），见下方 MODULE 模块层。


; ═══════════════════════════════════════════════════════════════════════════
;  ③ 保存与持久化
; ═══════════════════════════════════════════════════════════════════════════

#Include modules\SevenNote\Features\LoadFeature.ahk


#Include modules\SevenNote\Features\SaveFeature.ahk


#Include modules\SevenNote\Features\AutoSaveFeature.ahk


; 时间戳：v2.9 起移交页面（Ctrl+T）。
; ⚠ v2.16 删除了另外两条页面快捷键：Ctrl+H（插分隔线）与 Ctrl+Shift+H（插「新分段」）。
;   它们是为旧版纯文本 RichEdit 补的；Markdown 里直接打 `---` / `## ` 就会即时渲染，
;   快捷键反而多一步（「新分段」还得先选中占位文字）。用户 2026-10-23 反馈后删除。


; ═══════════════════════════════════════════════════════════════════════════
;  ④ 查看与浏览
; ═══════════════════════════════════════════════════════════════════════════

; 搜索 / 字数 / 光标记忆：v2.9 起移交页面。
; 搜索走浏览器原生 Ctrl+F（已通过 IID_3 关掉 AreBrowserAcceleratorKeysEnabled 之外的键），
; 字数由前端按 markdown 算，光标由 Milkdown 自己记。


; ═══════════════════════════════════════════════════════════════════════════
;  ⑤ 组织与管理
; ═══════════════════════════════════════════════════════════════════════════

#Include modules\SevenNote\Features\DateSwitchFeature.ahk


#Include modules\SevenNote\Features\DateJumpFeature.ahk


#Include modules\SevenNote\Features\TitleFeature.ahk


#Include modules\SevenNote\Features\GoTodayFeature.ahk


; ═══════════════════════════════════════════════════════════════════════════
;  横切 · 美观
; ═══════════════════════════════════════════════════════════════════════════

; 主题 / 字体：v2.9 起由页面自己管（CSS 变量，Alt+T 在前端实现，见 S3d）。
; ThemeService / FontService 仍在 —— 平台的语义色板与笔记模块的字号档位都由它们持有。
#Include modules\SevenNote\HostBridge.ahk
#Include modules\SevenNote\SevenNoteModule.ahk


; ═══════════════════════════════════════════════════════════════════════════
;  MODULE 模块层 · Launcher（Phase 3a：外部程序呼出）
; ═══════════════════════════════════════════════════════════════════════════

#Include modules\Launcher\Features\PowerShellFeature.ahk
#Include modules\Launcher\Features\DeepSeekFeature.ahk
#Include modules\Launcher\Features\AppSlotFeature.ahk
#Include modules\Launcher\LauncherModule.ahk


; ═══════════════════════════════════════════════════════════════════════════
;  MODULE 模块层 · KeysInput（Phase 4：键位增强）
; ═══════════════════════════════════════════════════════════════════════════

#Include modules\KeysInput\Features\CapsLockFeature.ahk
#Include modules\KeysInput\KeysInputModule.ahk


; ═══════════════════════════════════════════════════════════════════════════
;  MODULE 模块层 · Text（Phase 6：文本 / 片段库 —— 首个功能是提示词工程）
; ═══════════════════════════════════════════════════════════════════════════
; 与 SevenNote（时间流）并列的第二个「数据面」模块：按分类 + 标题收纳可复用片段。
; 数据在 <Vault>\_prompts\，目录即分类、文件名即标题 —— 外部编辑器也能改。
; 顺序有意义：#Include 的先后就是类的可用性，模块类必须最后引入。

#Include modules\Text\Services\PromptStoreService.ahk
#Include modules\Text\HostBridge.ahk
#Include modules\Text\Features\PromptWindowFeature.ahk
#Include modules\Text\Features\PromptEditFeature.ahk
#Include modules\Text\TextModule.ahk


; ═══════════════════════════════════════════════════════════════════════════
;  MODULE 模块层 · Folders（Phase 7：文件夹槽位 —— 热键写死、目标可换）
; ═══════════════════════════════════════════════════════════════════════════
; 与前两个「数据面」模块都不同：本模块**不建自己的窗口**，只负责把系统的资源管理器
; 窗口喊出来 / 收起来（容器由 Explorer 提供）。
;
; 核心：文件夹太多，一个目录配一个热键会吃光键盘 —— 所以固定 Alt+1/2/3 三个槽位，
; 每个槽位指哪个目录写在 _config.ini 的 [Folders]，随时可按需替换；
; 替换入口在 Alt+S 呼出的工作台面板里（模块自己声明设置字段，平台只负责渲染）。
;
; 另有一条 Alt+M：把资源管理器里**选中的文件**交给 pandoc 转成同名 .md（存同级目录）。
; 它的输入是「选中项」而不是槽位，所以是 explorer 上下文热键 —— 只在资源管理器前台
; 响应，不会去抢别的程序里的 Alt+M。
;
; 顺序有意义：#Include 的先后就是类的可用性，模块类必须最后引入。

#Include modules\Folders\Services\FolderSlotService.ahk
#Include modules\Folders\Services\FileConvertService.ahk
#Include modules\Folders\Features\FolderWindowFeature.ahk
#Include modules\Folders\Features\ConvertFeature.ahk
#Include modules\Folders\FoldersModule.ahk


; ═══════════════════════════════════════════════════════════════════════════
;  MODULE 模块层 · Vision（视界：三区域的用户入口）
; ═══════════════════════════════════════════════════════════════════════════
; 区域几何与摆放都在平台 ZoneService；本模块只提供 Alt+Shift+V 与面板说明。
; 删掉它，笔记 / 应用 / 文件的落位照常工作（只是没有一键恢复）。

#Include modules\Vision\VisionModule.ahk


; ═══════════════════════════════════════════════════════════════════════════
;  MODULE 模块层 · Theme（外观）
; ═══════════════════════════════════════════════════════════════════════════
; ⚠ 这不是「主题本身」—— 主题运行期仍在 WorkBench\Services\ThemeService；
;   本模块只是「当前主题」的用户入口（有多套主题后再在这里选）。
;   删掉它，所有窗口照样上色（只是没法看 / 换）；反过来让 ThemeService 调本模块
;   就是 Service → Module 的反向依赖，.clinerules/02 禁止。
; 没有热键、没有窗口：成文着的那几个外观滑杆已撤掉（观感由主题自己给全）。

#Include modules\Theme\ThemeModule.ahk


; ═══════════════════════════════════════════════════════════════════════════
;  组合根 —— 装配 + 启动
; ═══════════════════════════════════════════════════════════════════════════

; ═══ 全局异常兜底 ═══
; AHK v2 对未捕获异常默认是**弹模态框**：框一弹脚本就停摆（热键全无反应、框还挂在
; 屏幕上），只能手动杀进程 —— 项目在 v2 迁移期踩过三次（见 .clinerules/03）。
; 这里改成「写日志 + 继续跑」：单个 Feature 出错不该拖垮整个程序。
; 注册点放在这里（而不是文件更早处）是因为 LogError 要先建日志目录
; （%AppData%\SevenWork\），而那个目录就在下面几行才建。
OnError(OnScriptError)

; ═══ 事件总线的错误出口 ═══
; EventBus 属于 Kernel，不能直接引用 LogError（.clinerules/02「严禁反向依赖」），
; 所以由组合根把日志函数**注入**进去。必须早于任何 EventBus.Emit ——
; SevenNoteModule.Init() 里 State.SetGui() 就会发第一次 Gui.Ready。
; 没注入的代价：订阅者异常只写 OutputDebug，普通使用者看不到。
EventBus.SetErrorSink(LogError)

; AHK 的异常回调。返回 **1** = 已处理，不弹默认错误框（返回 0 就会弹）。
; ⚠ 回调自身绝不能抛异常 —— 会递归回到这里，所以全程 try，见 LogError。
OnScriptError(err, mode) {
    stack := err.HasProp("Stack") ? err.Stack : ""
    LogError(mode . "  " . err.Message
        . "`n      文件  " . err.File . "   行  " . err.Line
        . (Trim(stack) != ""
            ? "`n      调用栈：`n      " . StrReplace(Trim(stack, "`n"), "`n", "`n      ")
            : ""))
    return 1
}

; 追加一条到日志（落点见 Config.LogPath：%AppData%\SevenWork\_error.log）。
; 超 512 KB 就轮转（删掉重来）—— 日志只用来事后定位，不归档。
LogError(msg) {
    entry := "── " . FormatTime(, "yyyy-MM-dd HH:mm:ss") . " ──`r`n" . msg . "`r`n`r`n"
    try {
        logPath := Config.LogPath
        DirCreate(Config.LogDir)      ; 启动极早期出错时，这个目录可能还没建
        if (FileExist(logPath) && FileGetSize(logPath) > 524288)
            FileDelete(logPath)
        FileAppend(entry, logPath, "UTF-8")
    } catch {
        ; 项目目录只读 / 被占用时退回 AppData —— 日志丢一次就白查了
        try {
            fallbackDir := Config.AppDataDir
            DirCreate(fallbackDir)
            FileAppend(entry, fallbackDir . "\_error.log", "UTF-8")
        }
    }
}

; ═══ Phase 6：旧版数据迁移 ═══
; 新路径已有同名项时一律跳过；旧目录原样保留，确认新配置可用后再由用户删除。
; 复制失败不阻断启动 —— 新目录会退回默认配置 / 重新创建 profile。
MigrateLegacyAppData() {
    oldDir := A_AppData . "\SevenNote-Dev"
    if !DirExist(oldDir)
        return

    oldConfig := oldDir . "\_config.ini"
    if !FileExist(Config.ConfigPath) && FileExist(oldConfig)
        try FileCopy(oldConfig, Config.ConfigPath, false)

    ; DeepSeek profile 是独立 Edge 用户目录（约 950MB），只在目标不存在时整目录复制
    oldProfile := oldDir . "\_deepseek-profile"
    newProfile := Config.AppDataDir . "\_deepseek-profile"
    if !DirExist(newProfile) && DirExist(oldProfile)
        try DirCopy(oldProfile, newProfile, false)

    ; 模式是小文件；pid 指向旧进程，绝不复制
    oldMode := oldDir . "\_deepseek.mode"
    newMode := Config.AppDataDir . "\_deepseek.mode"
    if !FileExist(newMode) && FileExist(oldMode)
        try FileCopy(oldMode, newMode, false)

    ; pandoc 也是跨版本共用的独立目录；旧文件存在就不必重新解包
    oldPandoc := A_AppData . "\SevenNote\pandoc.exe"
    if !FileExist(Config.PandocPath) && FileExist(oldPandoc)
        try FileCopy(oldPandoc, Config.PandocPath, false)
}

; ═══ 确保 AppData 目录存在 ═══
DirCreate(Config.AppDataDir)

; ═══ Phase 6：迁移旧版 SevenNote-Dev 数据 ═══
; 只在新路径缺失时复制，旧目录保留；DeepSeek profile 约 950MB，
; 首次升级启动会多花几秒，之后各路径已存在就直接跳过。
MigrateLegacyAppData()

; ═══ 打包 pandoc.exe（v1.9 修复）═══
; 【关键修复】
;   · FileInstall 必须一行，不能折行（否则 Ahk2Exe 可能打包空文件）
;   · 第二参数用展开的表达式，不用类属性
;   · 释放前先删旧文件（避免 0KB 坏文件阻塞后续释放）
;   · 只在文件不存在或 < 1MB 时才释放
; ⚠ 编译前把下面的源路径改成你本机 pandoc.exe 的实际路径
; ⚠ 编译时务必确认源文件是 100+ MB 的 x86_64 版 pandoc
if !FileExist(Config.PandocPath) || FileGetSize(Config.PandocPath) < 1048576 {
    try FileDelete(Config.PandocPath)
    FileInstall "C:\Users\Seven\AppData\Local\Pandoc\pandoc.exe", A_AppData . "\SevenWork\pandoc.exe", 1
}

; ═══ 配置服务初始化 ═══
ConfigService.Init(Config.ConfigPath)
ConfigService.SetDefault("Appearance", "ThemeIndex", "1")
; 主题表「结构版本」：主题表精简 / 重排过就 +1，ThemeService._MigrateIndex 据此只跑一次下标迁移
ConfigService.SetDefault("Appearance", "ThemeSchema", "1")
ConfigService.SetDefault("Appearance", "FontIndex", "1")
ConfigService.SetDefault("Appearance", "FontSizeIndex", "2")
ConfigService.SetDefault("Input", "CapsLockMap", "0")
ConfigService.SetDefault("Paths", "Vault", "")

; ═══ 首次运行：引导用户选择笔记目录 ═══
EnsureVaultConfigured()

; ═══ 确保笔记目录存在 ═══
DirCreate(Config.GetVault())

; ═══ 工作台装配（模块登记 + 面板就绪）═══
; 必须在模块 Init() 之前：订阅要赶在第一次 Alt+C / Alt+X 之前就位。
WorkBench.Init()

; ═══ 统一启动（第一段）：遍历登记表，逐个 Init ───
; 加模块只改两处，都在 WorkBench.Init() 里：一行 #Include、一行 Register。
; 这里不再逐个手写模块名 —— 一个模块 Init 抛错不带走后面（失败记日志 + 跳过其热键）。
ModuleRegistry.InitAll()

; ═══ 热键（Router 聚合平台 + 各模块的 GetHotkeys）═══
HotkeyRouter.RegisterAll()

; ═══ 统一启动（第二段）：对外可见 —— 加载笔记 / 恢复配置 / 应用 CapsLock 映射 ═══
; 必须晚于热键注册：否则窗口先露面、热键还没就位，按 Alt+Z 会「没反应」。
ModuleRegistry.StartAll()

ShowStartupTip()


; ═══════════════════════════════════════════════════════════════════════════
;  首次运行引导
; ═══════════════════════════════════════════════════════════════════════════

EnsureVaultConfigured() {
    vault := ConfigService.Read("Paths", "Vault")
    if (vault != "" && DirExist(vault))
        return

    defaultPath := A_MyDocuments . "\SevenWork"
    if (vault != "")
        defaultPath := vault

    selected := DirSelect(defaultPath, 0
        , Config.AppName . " 首次运行`n`n请选择笔记存储目录：")
    if (selected = "")
        selected := defaultPath

    DirCreate(selected)
    Config.SetVault(selected)
}


; ═══════════════════════════════════════════════════════════════════════════
;  启动提示
; ═══════════════════════════════════════════════════════════════════════════

ShowStartupTip() {
    ; 启动提示也跟主题走：WorkBench.Init() 里已 LoadFromConfig()，此处拿到的一定是最新一套。
    ; 平台级窗口只读色板、不订阅 Theme.Changed —— 它只活 1.5 秒，没必要为它挂订阅。
    p := ThemeService.Palette()
    tip := Gui("-MinimizeBox -MaximizeBox +AlwaysOnTop", "提示")
    tip.SetFont("s14", "楷体")
    tip.BackColor := p.win
    ; 平台级提示只指向平台级热键：Alt+S 打开工作台（里面才有模块热键 Alt+Z 等）。
    ; 上下两行：一行要 314 逻辑像素、横条太宽观感差；拆开后每行 ≤153，窗口回到窄条 w240。
    ; 控件 h48 是两行高度（单行约 18.7），窗口 h80 容得下（y16 + 48 = 64）。
    tip.AddText("x20 y16 w200 h48 Center c" . p.text
        , Config.AppName . " 已启动！`nAlt+S 打开工作台")
    UiPaint.TitleBar(tip.Hwnd, p.win, p.text)
    ; 启动提示也吃玻璃：它活在桌面上，背衬比底色更显眼
    UiPaint.Glass(tip.Hwnd, p.style, p.win)
    tipY := A_ScreenHeight * 0.65
    tip.Show("w240 h80 y" . tipY)
    ; ⚠ 1.5 秒内用户可能自己把这扇提示窗关掉 —— 再 Destroy() 一次会抛异常，
    ;   而 SetTimer 回调没有外层 try，异常即弹模态框（见 .clinerules/03）。
    SetTimer(() => DestroyTipWindow(tip), -1500)
}

; 关掉启动提示。已经关过就算了 —— 这正是 try 的用途。
DestroyTipWindow(tip) {
    try tip.Destroy()
}
