#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════════
;  WorkBench —— 平台组合根（Phase 3b）
; ═══════════════════════════════════════════════════════════════════════════
; 只做平台级装配：登记模块、初始化事件协调器与界面占位。
; 各模块自己的 Feature 生命周期仍由 Module.Init() 负责，平台不越层调用。
class WorkBench {
    static _initialized := false

    ; 「上一次保存成功了吗」—— 退出热键据此决定走不走。
    ; ⚠ EventBus.Emit 没有返回值，所以用结果标志接：NoteSessionService 成功时发
    ;   Save.Completed，失败只发 Note.Status（带 err）。两者都没来 = 没人处理 = 不退出。
    static _saveOk := false

    static Init() {
        if this._initialized
            return
        this._initialized := true

        ; ─── 先恢复主题：模块 Init 会读它（主窗底色 / WebView2 首帧色）───
        ; 必须在 Register / InitAll 之前 —— 否则第一个窗口建出来就是主题 1。
        ; LoadFromConfig 只改状态、不广播：此刻窗口一个都还没建，没人要重绘。
        ThemeService.LoadFromConfig()

        ; 模块登记只放「模块类」——它们统一带 Id / Name / Init() / GetHotkeys()。
        ; ⚠ 加模块只改这里（一行 #Include 在上面）+ 一行 Register，组合根不动：
        ;   启动 / 热键 / 兜底都由 ModuleRegistry.InitAll() / StartAll() / HotkeyRouter 遍历。
        ModuleRegistry.Register(SevenNoteModule)
        ModuleRegistry.Register(LauncherModule)
        ModuleRegistry.Register(KeysInputModule)
        ModuleRegistry.Register(TextModule)
        ModuleRegistry.Register(FoldersModule)
        ; 外观：只提供「调全局外观参数」的设置页，不持有主题、不建窗口。
        ; 放在最后注册 —— 它不参与启动顺序，order 5 决定它在面板里的位置。
        ModuleRegistry.Register(ThemeModule)

        ; Phase 3b：先挂上 Launcher.Opened / SevenNote.WindowReady 的监听。
        PeerCoordinator.Init()
        WebPanelUI.Init()

        ; 只认成功信号（空笔记 / 无改动也算成功）
        EventBus.On("Save.Completed", (*) => WorkBench._OnSaved())
    }

    static _OnSaved() {
        WorkBench._saveOk := true
    }

    ; ─── 平台级热键：工作台面板 + 主题 + 保存退出 ───
    ; Alt+S 由平台负责打开面板（帮助 + 各模块设置）；Alt+Shift+Z 只广播 Save.Requested，
    ; 真正落盘仍由 SevenNote 的 SaveFeature 订阅处理 —— 平台不直接调用模块内部 Feature。
    ; Alt+T 归平台：主题是**所有模块窗口**共用的一套（v2.9 起 ThemeService 上收到平台），
    ; 不再是笔记模块的私事 —— 放在模块里会让「谁负责切主题」取决于模块是否启用。
    static GetHotkeys() {
        return [
            {ctx: "global", key: "!s", group: "平台", line: "   Alt+S            工作台面板（帮助 + 设置）"
                , fn: (*) => WebPanelUI.ShowHelp()},
            {ctx: "global", key: "!t", group: "外观", line: "   Alt+T            循环切换界面主题"
                , fn: (*) => ThemeService.Next()},
            {ctx: "global", key: "!+z", group: "平台", line: "   Alt+Shift+Z      保存并退出"
                , fn: (*) => WorkBench.SaveAndExit()}
        ]
    }

    ; ─── 保存并退出 ───
    ; ⚠ 保存失败**不退**：退出等于放弃这次改动，而用户看不到任何提示。
    ;   平台不直接调 SevenNote 的 SaveFeature（反向依赖），只发事件 + 看结果标志。
    static SaveAndExit() {
        this._saveOk := false
        EventBus.Emit("Save.Requested")
        if this._saveOk
            ExitApp()

        ; 走到这里 = 没存上。留在原地，把原因摆到鼠标旁（窗口收起时状态栏看不见）
        try ToolTip("保存失败，已取消退出`n详情见 %AppData%\SevenWork\_error.log")
        SetTimer(() => ToolTip(), -3500)
    }

    static GetMetadata() {
        return {name: "平台", desc: "工作台", order: 0, hotkeys: this.GetHotkeys()}
    }
}
