#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════════
;  PromptWindowFeature —— 提示词库主窗口（模块：Text）
; ═══════════════════════════════════════════════════════════════════════════
; 职责：窗口显隐 / 定位到某一条 / 复制正文 / 转交编辑窗。
; 不碰磁盘 —— 读写全归 PromptStoreService；不做编辑窗的业务 —— 只负责打开它。
;
; v2.10 起这个窗口是一个网页（web\src\components\PromptView.vue，走 ?view=prompts）。
; 生命周期（建窗 / 隐藏态定位 / 露面后挂载 / Esc / 换主题）全在 WorkBench\WebWindow.ahk
; —— 每个 WebView2 窗口都一样，抄一遍就多一处坑（见 .clinerules/02「一律走 WebWindow」）。
;
; 交互（用户 2026-10-20 定调，v2.10 未变）：
;   单击        → 只选中，既不复制也不编辑
;   Enter       → 进入编辑窗口（改标题 / 分类 / 正文）
;   双击        → 直接复制到剪贴板 + 窗口立即收起（复制是高频动作：一发拿到就走）
;   Esc         → 隐藏
;
; 配色：读平台主题（ThemeService.Palette()）。建窗时由 WebWindow 上色；之后按 Alt+T
; 走 OnThemeChanged() —— 只推 CSS 变量、**不重建**（停在哪、搜了什么都还在）。
;
; 落点：辅助区中心（place: "zone"）。提示词库是随手呼出的浮层，不参与区域注册，
; 也不影响笔记的记录区。
; ═══════════════════════════════════════════════════════════════════════════

class PromptWindowFeature {
    static _win := ""        ; WebWindow 实例（首次呼出时才建，启动时不多一个隐藏窗口）
    static _focusId := ""    ; 编辑窗保存 / 删除后要定位的 path（空 = 不定位）
    static _tipTimer := ""   ; 复制时那条 ToolTip 的清除定时器（闭包引用）

    ; ═══ 窗口 ═══

    static _Window() {
        if !IsObject(this._win)
            this._win := WebWindow({
                title:    Config.AppName . " · 提示词库"
              , w:        620
              , h:        520
              , view:     "prompts"
              , dataDir:  "prompts"
              , handlers: PromptHostHandlers
              , place:    "zone"
              , zone:     "aux"
              , esc:      () => this.Hide()
            })
        return this._win
    }

    ; 窗口句柄；未建 / 已被销毁都返回 0
    static Hwnd() {
        if !IsObject(this._win)
            return 0
        return this._win.Hwnd()
    }

    ; 是否真的「看得见」。⚠ 最小化窗口的 IsWindowVisible 仍是 1，必须同时排掉 IsIconic
    static IsShowing() {
        hwnd := this.Hwnd()
        if !hwnd
            return false
        return !!DllCall("IsWindowVisible", "ptr", hwnd, "int")
            && !DllCall("IsIconic", "ptr", hwnd, "int")
    }

    static Toggle() {
        if this.IsShowing()
            this.Hide()
        else
            this.Show()
    }

    static Show() {
        ; 用户主动呼出 = 只要重新扫一遍，不要被甩回上次编辑的那条
        this._focusId := ""
        this._Window().Open()
        ; 每次呼出都让页面重扫：文件可能在程序外被改（VS Code / 资源管理器）。
        ; 窗口刚建时页面还没起来，这次 Eval 会落空 —— 页面 onMounted 自己还会拉一次。
        this._Pull()
    }

    static Hide() {
        if IsObject(this._win)
            this._win.Close()
    }

    ; 换主题（Alt+T）：只换窗口底色 + 推 --sw-*，不重建
    static OnThemeChanged() {
        if IsObject(this._win)
            this._win.ApplyTheme()
    }

    ; ═══ 给宿主 / 编辑窗用的 ═══

    ; 编辑窗保存 / 删除之后要回到的那一条（页面拉数据时读它）
    static FocusId() => this._focusId

    ; path 为空 = 只重拉不定位（删除之后那一条已经没了）
    static FocusPath(path) {
        this._focusId := ("" . path)
        this._Pull()
    }

    ; F5：忽略缓存重扫（文件可能在程序外被改）
    static Reload(*) {
        this._focusId := ""
        this._Pull()
    }

    ; 让页面重新拉一次数据。
    ; ⚠ 窗口没建 / 页面还没起来时 Eval 返回 {ok:false}，忽略即可 —— 页面自己会再拉。
    static _Pull() {
        if !IsObject(this._win) || !this._win.IsOpen()
            return
        WebHostService.Eval("window.__swprompt&&window.__swprompt.reload()", this.Hwnd())
    }

    ; 保存 / 删除之后的确认。此时列表窗通常开着（编辑窗是另一个窗口），
    ; 让页面状态栏显示几秒再自己回落 —— 回落归前端，AHK 不排定时器。
    static Notify(msg) {
        if !IsObject(this._win) || !this._win.IsOpen()
            return
        WebHostService.Eval("window.__swprompt&&window.__swprompt.status("
            . JsText.Escape(msg) . ")", this.Hwnd())
    }

    ; ═══ 动作 ═══

    ; Enter → 编辑选中的那一条。
    ; ⚠ 「选中」在前端（DOM 里），AHK 这边看不见 —— 所以只发指令，由页面自己决定
    ;   当前是哪条，再回调 edit(path)。反过来「每次选择变化都同步一次 path」等于
    ;   给一次鼠标点击加一趟跨进程调用，不值。
    static EditSelected() {
        if IsObject(this._win) && this._win.IsOpen()
            WebHostService.Eval("window.__swprompt&&window.__swprompt.editSelected()"
                , this.Hwnd())
    }

    ; 新建（Ctrl+N / 页面上的「新建」按钮）→ 直接开编辑窗，不必绕前端
    static NewPrompt(*) {
        if PromptEditFeature.Open("")
            return
        try ToolTip("打开新建提示词窗口失败（详见 _error.log）")
        SetTimer(() => ToolTip(), -4000)
    }

    ; 双击 / 页面按钮：复制正文并给个鼠标旁的确认。返回 "ok" / "err:原因"。
    ; ⚠ **不在这里收窗** —— 收窗由前端拿到 "ok" 之后自己调 close：失败的提示
    ;   要留在窗口里给用户看见（收了就看不到了）。
    static CopyPath(path) {
        for it in PromptStoreService.LoadAll() {
            if (it.path != path)
                continue
            try A_Clipboard := it.text
            catch
                ; 剪贴板被别的进程占着（远程桌面 / 剪贴板管理器会这样）
                return "err:复制失败：剪贴板被占用"
            this._Tip("已复制「" . it.title . "」")
            return "ok"
        }
        return "err:条目不存在（可能已被删或改名）"
    }

    ; 打开编辑窗。path 为空 = 新建。
    static EditPath(path) {
        if (path = "") {
            if PromptEditFeature.Open("")
                return "ok"
            return "err:打开新建提示词窗口失败（详见 _error.log）"
        }
        for it in PromptStoreService.LoadAll() {
            if (it.path = path) {
                if PromptEditFeature.Open(it)
                    return "ok"
                return "err:打开提示词编辑窗口失败（详见 _error.log）"
            }
        }
        return "err:条目不存在（可能已被删或改名）"
    }

    ; 轻量确认：窗口已收起时状态栏看不见，就在鼠标旁闪一下
    static _Tip(msg) {
        try ToolTip(msg)
        this._StopTipTimer()
        timerFn := () => this._ClearTip()
        this._tipTimer := timerFn
        SetTimer(timerFn, -1200)
    }

    static _StopTipTimer() {
        timerFn := this._tipTimer
        this._tipTimer := ""
        if IsObject(timerFn)
            try SetTimer(timerFn, 0)
    }

    static _ClearTip(*) {
        this._tipTimer := ""        ; 自然触发后也要放掉引用，别让字段一直攥着闭包
        try ToolTip()
    }
}
