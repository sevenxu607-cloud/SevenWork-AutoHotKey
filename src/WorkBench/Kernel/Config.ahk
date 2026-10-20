#Requires AutoHotkey v2.0
; WorkBench/Kernel/Config.ahk
; Moved from SevenNote.ahk (Phase 1). Implementation unchanged.

class Config {
    static AppName := "SevenWork"
    static Version := "2.8"

    ; ⚠ 配置目录与 pandoc 目录**故意不同**，不是笔误：
    ;   · _config.ini 是使用者状态（主题 / 字体 / Vault 路径），按身份隔离 ——
    ;     开发版走 SevenWork-Dev，运行版走 SevenWork，切换时不会互相覆盖配置。
    ;   · pandoc.exe 是 100+MB 的内嵌可执行文件，跨版本共用一份，不随配置目录搬家。
    ; ⚠ 用 `=>` 简写属性：A_IsCompiled 在取值时才求值，源码运行与编译版各走各的目录。
    ;
    ; ═══ 【运行版分支专用】源码运行也走 SevenWork ═══
    ; 与 main 的区别就在这一处：main 上源码运行走 SevenWork-Dev（开发配置，
    ; Vault 指测试库），本分支用于「拿真实笔记正常使用几天」，所以配置、日志
    ; 都与编译版同目录，读的正是旧单文件版留下的那份 _config.ini。
    ; 两分支靠这一处差异隔离 —— **切分支即切身份**，互不污染；
    ; 把本改动合回 main 会让开发版直接读写生产配置，合并时务必只挑需要的提交。
    static AppDataDir => A_AppData . "\SevenWork"
    static ConfigPath => this.AppDataDir . "\_config.ini"
    static PandocPath := A_AppData . "\SevenWork\pandoc.exe"

    ; 报错日志落点：本分支是**使用态**，日志跟随配置落 AppData；
    ; main 上的开发版才写项目根 `.logs\`（翻起来不用到处找）。
    ; 编译版历来落 AppData —— exe 可能在桌面 / U 盘 / Program Files，那里
    ; 要么往用户目录里扔文件，要么根本没写权限。
    ; ⚠ 用 `=>` 简写属性而不是 `:=`：A_IsCompiled / A_ScriptDir 在取值时才求值，
    ;   不在类加载期赌内置变量是否已就绪。
    ; ⚠ 这两个身份别塞进上面的声明里 —— 它们依赖运行时内置变量。
    static LogDir => this.AppDataDir
    static LogPath => this.LogDir . "\_error.log"

    static GetVault() {
        v := ConfigService.Read("Paths", "Vault")
        if (v = "")
            return A_MyDocuments . "\SevenWork"
        return v
    }
    static SetVault(path) => ConfigService.Write("Paths", "Vault", path)

    ; 提示词库根目录（Text 模块的数据面）。
    ; 默认挂在 Vault 下的 `_prompts\` —— 数据跟着笔记库走，备份 / 迁移只有一处。
    ; 想让它独立（单独同步、放别的盘）就在 _config.ini 写 `[Paths] PromptsDir=...`，
    ; 非空即覆盖。留这个口子是为了「不逼用户把两类数据绑死」，默认则零配置。
    static GetPromptsDir() {
        d := ConfigService.Read("Paths", "PromptsDir")
        if (d = "")
            return this.GetVault() . "\_prompts"
        return d
    }

    ; 首次呼出时窗口距屏幕工作区右边 / 顶边的距离（物理像素）
    static PlaceRight := 15
    static PlaceTop := 264
    static AutoSaveInterval := 120000
    ; 字数 / 滚动同步的巡检间隔。**150ms 是实测出来的**（v2.4.4）：
    ;   · 巡检本身几乎免费 —— 1000 次 `GetScrollInfo` 实测 0ms；
    ;   · 真正花钱的只有「检测到脱节」后那一次 `EM_SETSCROLLPOS` 重排（小窗 2.4ms/次）；
    ;   · 500ms 时删掉一片空行，画面要等半秒才「啪」地跳一次 —— 用户报的「生硬」；
    ;   · 50ms 那版在真机上出过问题（删除过程中逐帧重排，画面抽搐）。
    ;   150ms 让删除过程中画面每 150ms 跟一次、删完立刻收尾，且不会逐帧重排。
    static StatInterval := 150
    ; 双窗并存（Alt+C 唤起 PowerShell / Alt+X 唤起 DeepSeek）时的「可见」间距（物理像素）：
    ; 两窗之间的缝、窗口到工作区顶/底的边距。
    ; ⚠ 这里算的是**肉眼看到**的距离 —— 按 DWM 的可见边界算，不含 Win11 的不可见调整边框。
    ;   本机实测 `WinGetPos` 的矩形比可见边界每边多 9px（左 −9 / 上 0 / 右 9 / 下 9），
    ;   若直接按矩形拼，设 12 的缝看上去会是 12 + 9 = 21。
    static DockGap := 6
    static DockMargin := 10
}
