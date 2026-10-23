#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════════
;  WorkBench —— 平台组合根（Phase 3b）
; ═══════════════════════════════════════════════════════════════════════════
; 只做平台级装配：登记模块、初始化事件协调器与界面占位。
; 各模块自己的 Feature 生命周期仍由 Module.Init() 负责，平台不越层调用。
class WorkBench {
    static _initialized := false

    ; ─── 退出守卫 ─────────────────────────────────────────────────────────
    ; 模块在 Init() 里发 `Exit.Guard` 事件登记自己那一条检查（笔记保存、提示词未保存），
    ; 平台只认「返回 {ok, reason} 的函数」，不认识任何业务名词。
    ; ⚠ 为什么不订阅「某次保存成功」的全局信号：那只证明**某一个**模块存过盘，
    ;   不代表提示词窗里没有没存的内容。退出必须逐条问，缺一条就是静默丢数据。
    static _exitGuards := Map()

    ; 防重入：退出检查会读写文件、可能把窗口摆到前台，用户连按热键不该叠加执行。
    static _exiting := false

    static Init() {
        if this._initialized
            return
        this._initialized := true

        ; ─── 先恢复主题：模块 Init 会读它（主窗底色 / WebView2 首帧色）───
        ; 必须在 Register / InitAll 之前 —— 否则第一个窗口建出来就是主题 1。
        ; LoadFromConfig 只改状态、不广播：此刻窗口一个都还没建，没人要重绘。
        ThemeService.LoadFromConfig()

        ; ⚠ 必须早于 ModuleRegistry.InitAll()：模块是在自己的 Init() 里发这个事件的，
        ;   晚一步订阅就一条都收不到（表现为「退出时没人检查」）。
        EventBus.On("Exit.Guard", (data) => WorkBench._AddExitGuard(data))

        ; 模块登记只放「模块类」——它们统一带 Id / Name / Init() / GetHotkeys()。
        ; ⚠ 加模块只改这里（一行 #Include 在上面）+ 一行 Register，组合根不动：
        ;   启动 / 热键 / 兜底都由 ModuleRegistry.InitAll() / StartAll() / HotkeyRouter 遍历。
        ModuleRegistry.Register(SevenNoteModule)
        ModuleRegistry.Register(LauncherModule)
        ModuleRegistry.Register(KeysInputModule)
        ModuleRegistry.Register(TextModule)
        ModuleRegistry.Register(FoldersModule)
        ; 外观：只提供「当前主题」的展示页（多主题后在这里选），不持有主题、不建窗口。
        ; 放在最后注册 —— 它不参与启动顺序，order 5 决定它在面板里的位置。
        ModuleRegistry.Register(ThemeModule)

        ; Phase 3b：先挂上 Launcher.Opened / SevenNote.WindowReady 的监听。
        PeerCoordinator.Init()
        WebPanelUI.Init()
    }

    static _AddExitGuard(data) {
        if !IsObject(data) || !data.HasProp("id") || !data.HasProp("check")
            return
        check := data.check
        if !IsObject(check)
            return
        ; 同名重复登记时后一条覆盖前一条 —— 不会出现同一份内容被检查两次。
        this._exitGuards[data.id] := check
    }

    ; ─── 平台级热键：工作台面板 + 主题 + 退出 ───
    ; Alt+S 由平台负责打开面板（帮助 + 各模块设置）；
    ; Alt+Shift+S 走退出流程：先逐个问「有没有不能丢的东西」，通过了才 ExitApp()。
    ; ⚠ 平台不直接调模块内部 Feature（反向依赖），只调模块登记的退出守卫。
    ; Alt+T 归平台：主题是**所有模块窗口**共用的一套（v2.9 起 ThemeService 上收到平台），
    ; 不再是笔记模块的私事 —— 放在模块里会让「谁负责切主题」取决于模块是否启用。
    static GetHotkeys() {
        return [
            {ctx: "global", key: "!s", group: "平台", line: "   Alt+S            工作台面板（帮助 + 设置）"
                , fn: (*) => WebPanelUI.ShowHelp()},
            {ctx: "global", key: "!t", group: "外观", line: "   Alt+T            循环切换界面主题"
                , fn: (*) => ThemeService.Next()},
            {ctx: "global", key: "!+s", group: "平台"
                , line: "   Alt+Shift+S      退出（有未保存内容会先拦下）"
                , fn: (*) => WorkBench.RequestExit()}
        ]
    }

    ; ─── 退出 ─────────────────────────────────────────────────────────────
    ; 顺序：模块守卫 → 面板未保存的设置 → 全通过才退出。
    ; ⚠ 不走「广播 Save.Requested 再看一个成功标志」：那只覆盖笔记，而且
    ;   一条失败会把所有成功都盖掉；现在每个模块自己说结果。
    static RequestExit() {
        if this._exiting
            return
        this._exiting := true

        reasons := []
        for id, fn in this._exitGuards {
            reason := this._RunGuard(id, fn)
            if (reason != "")
                reasons.Push(reason)
        }
        ; 面板里的设置字段只活在前端：没点「保存设置」就退出等于把它们丢掉。
        pending := this._PanelPending()
        if (pending != "")
            reasons.Push(pending)

        if reasons.Length {
            this._ExplainHold(reasons)
            this._exiting := false
            return
        }
        ExitApp()
    }

    ; 跑一条守卫。返回空串 = 通过；否则返回给人看的原因。
    ; ⚠ 守卫自己抛错一律当「没准备好」—— 宁可拒绝退出，也不能带着未保存的内容走。
    ; ⚠ 先把函数取到局部变量再调：`obj.prop(args)` 走方法查找，属性里存的 Func
    ;   会抛 Too many parameters，还会被这里的 catch 误当成「检查出错」。
    static _RunGuard(id, fn) {
        check := fn
        try r := check()
        catch as e {
            LogError("退出检查失败：" . id . " —— " . e.Message)
            return id . "：检查出错（" . e.Message . "）"
        }
        if IsObject(r) && r.HasProp("ok") && r.ok
            return ""
        if IsObject(r) && r.HasProp("reason") && r.reason != ""
            return id . "：" . r.reason
        return id . "：还没准备好"
    }

    ; 面板里有没有「改了但没点保存」的字段。
    ; ⚠ hasPending 是**纯前端比较**（当前编辑值 vs 配置值），不会再回调 AHK ——
    ;   这是它能在宿主调用栈里安全 await 的前提。页面没起来时返回 false。
    static _PanelPending() {
        if !WebPanelUI.IsOpen()
            return ""
        r := WebHostService.Eval(
            "window.__swpanel&&window.__swpanel.hasPending?window.__swpanel.hasPending():false"
            , WebPanelUI.Hwnd())
        if (r.ok && r.value = "true")
            return "面板：有未保存的设置（先点「保存设置」，或按 Esc 放弃改动）"
        return ""
    }

    ; 拦下退出时把原因摆到鼠标旁（窗口收起时状态栏看不见），并留一份日志。
    static _ExplainHold(reasons) {
        msg := "已取消退出"
        for reason in reasons
            msg .= "`n· " . reason
        try ToolTip(msg)
        SetTimer(() => ToolTip(), -6000)
        LogError("退出被拦下：" . msg)
    }

    static GetMetadata() {
        return {name: "平台", desc: "工作台", order: 0, hotkeys: this.GetHotkeys()}
    }
}
