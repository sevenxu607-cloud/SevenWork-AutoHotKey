#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════════
;  WindowFeature —— 笔记窗口的显隐与落位
; ═══════════════════════════════════════════════════════════════════════════
; Alt+Z 呼出 / 收起笔记窗口。窗口固定落在**记录区**（ZoneService）：
; 记录区 = 辅助区正上方、与辅助区同宽、顶贴工作区顶。
;
; v2.18 整段删除「伙伴窗口适配」：
;   以前呼出终端 / DeepSeek 会让笔记让位、堆叠、再冻结；现在笔记只认记录区，
;   终端 / 浏览器只认辅助区，两边互不联动。
;
; 位置不再记忆：记录区就是它的位置；用户手动拖走后，下次呼出仍回记录区。
; 区域不可用（小屏 no-fit / 窗口无效）时退回旧的右上角默认落点，保证还能用。

class WindowFeature {
    ; 组合根在 LauncherModule.Init() 之前调用；现在没有订阅，保留生命周期入口。
    static Init() {
    }

    ; ─── 入口：Alt+Z ───
    static Toggle() {
        if this.IsShowing()
            this.Hide()
        else
            this.Show()
    }

    ; 判断“当前是否正在显示”。
    ; 注意：最小化窗口的 WS_VISIBLE 仍是 1，必须连同 IsIconic 一起排除；
    ; 否则最小化状态下按 Alt+Z 会被误判成“正在显示”而执行隐藏，越按越找不着。
    static IsShowing() {
        hwnd := State.GetGuiHwnd()
        if !hwnd
            return false
        return DllCall("IsWindowVisible", "ptr", hwnd, "int")
            && !DllCall("IsIconic", "ptr", hwnd, "int")
    }

    ; ─── 收起：先存盘、再隐藏 ───
    static Hide() {
        g := State.GetGui()
        ; ⚠ 先存盘、存住了才收：收起等于「这次的改动先放着」，而保存失败时窗口一藏，
        ;   用户连状态栏那行提示都看不见，下次打开还是旧内容。
        ;   recoverable = 当前没有可丢的内容（冷启动 / 页面还没挂），那种放行。
        saved := NoteSessionService.Save()
        if !saved.ok && !(saved.HasProp("recoverable") && saved.recoverable) {
            reason := saved.HasProp("reason") ? saved.reason : "未知原因"
            ; 收起失败不能静默 —— 用户会以为窗口坏了。
            try ToolTip("笔记未能保存，窗口未关闭：" . reason)
            SetTimer(() => ToolTip(), -5000)
            return false
        }
        if !g
            return false

        ; 通知「即将收起」—— 保存已在上面做完，订阅者不用再存一次
        EventBus.Emit("Window.BeforeHide")
        ; ⚠ 必须显式传 hwnd：WebHostService 是多实例的（面板 / 提示词库 / 笔记窗各一份），
        ;   无参会落到「最近挂载的窗口」—— 收了笔记窗却把面板的入场状态复位掉，
        ;   两个窗口的动画从此互相干扰，而日志里一个字都不会有。
        try {
            WebHostService.Eval("window.__swfx&&window.__swfx.reset()", g.Hwnd)
            g.Hide()
        } catch as e {
            LogError("笔记窗口收起失败：" . e.Message)
            return false
        }
        return true
    }

    ; ─── 呼出：记录区定位 → 激活 ───
    ; v2.9：编辑区换成 WebView2 后，这里不再有 RichEdit 的「暂停重绘 / 还原光标」——
    ; 光标由页面自己管（Milkdown 会记住选区），重绘由 Chromium 合成。
    ; ⚠ 别把 _PlaceWindow 包进 try：它前后曾经挂着 SendMessage(0x000B)，而
    ;   GetEd() 现在恒为 0，那条 SendMessage 会抛错、把定位整段跳过 ——
    ;   表现是「按 Alt+Z 什么窗口都不出来」，而且日志里只有一句 Target window not found。
    static Show() {
        g := State.GetGui()
        ghwnd := g.Hwnd
        this._PlaceWindow(g, ghwnd)
        ; ⚠ g.Show() 已经激活过一次；这一句是为了「窗口早就存在、只是被别的窗口
        ;   盖住」的情况。它偶发抛 Target window not found（隐藏→可见那一瞬
        ;   WinTitle 匹配不到），而窗口其实已经出来了 —— 失败没有用户可见后果，
        ;   不该让它变成一条错误日志。先确认窗口确实可匹配，再激活。
        if WinExist("ahk_id " . ghwnd)
            try WinActivate("ahk_id " . ghwnd)
        EventBus.Emit("Window.Shown")
    }

    ; ═══ 定位 ═══

    ; 记录区定位：全程在隐藏态完成 —— Show("Hide") → 等尺寸稳定 → Place → Show()。
    ; ⚠ 反过来（先 Show 再 WinMove）会让窗口先在 AHK 默认落点露面、再跳到记录区，
    ;   实测约 190ms 后才到位，视觉上就是「飘一下」。
    ; ⚠ 区域不可用（小屏 / 窗口无效）时不硬摆：退回右上角默认落点，至少窗口在屏幕内。
    static _PlaceWindow(g, ghwnd) {
        detectOld := A_DetectHiddenWindows
        DetectHiddenWindows(true)
        try {
            g.Show("Hide")
            ; 等控件布局定型：Show("Hide") 之后 OnSize 还没跑完就设尺寸，
            ; 会被随后的布局盖回去。区域尺寸是固定的，这里只等稳定、不用测量值。
            w := 0, h := 0
            this._MeasureStable(ghwnd, &w, &h)

            res := ZoneService.Place(ghwnd, "record", {fill: true, allowHidden: true})
            if !res.ok
                this._MoveToDefault(g, ghwnd)
        } finally {
            DetectHiddenWindows(detectOld)
        }

        g.Show()
        this._EnsureVisible(ghwnd)
    }

    ; 把窗口从「最小化 / 隐藏残留」拉回正常显示。拿不到窗口就什么都不做 ——
    ; 这条路径上的失败没有用户可见后果（窗口已经 Show 出来了），不该刷日志。
    ;
    ; ⚠ 直接对 **hwnd** 调 ShowWindow(SW_SHOWNORMAL=9)，不用 WinRestore：
    ;   后者按 WinTitle 匹配，在「隐藏 → 可见」那一瞬会抛 Target window not found
    ;   （_error.log 里反复出现过）。ShowWindow 只认句柄，没有这个时间窗。
    ; ⚠ 这不是防御性冗余：实测重启后**第一次** Alt+Z，窗口已经 Show 出来、
    ;   WS_VISIBLE 也是 1，但 IsIconic 仍是 1 —— 屏幕上什么都没有，任务栏里躺着一个。
    ;   那一刻 WinRestore 正好匹配失败，而窗口看起来「按了没反应」。
    ;   对已是正常态的窗口调 SW_SHOWNORMAL 是无操作，可以每次调。
    static _EnsureVisible(ghwnd) {
        if !ghwnd
            return
        try DllCall("user32\ShowWindow", "ptr", ghwnd, "int", 9)
    }

    ; 等窗口尺寸稳定下来。Show 之后控件的固有尺寸要等 OnSize 跑完才反映到窗口外框上，
    ; 连续两次量到同一个值才认为定型。全程窗口不可见，多花几毫秒用户看不见。
    ;
    ; ⚠ **最小尺寸下限不能省**：Show("Hide") 之后 WinGetPos 可能先读到 10 一类的中途值，
    ;   而「连续两次相同」会把那个 10px 当成终值 —— 拿它算默认落点，窗口会整体偏到
    ;   屏幕右侧（只剩任务栏或边上一道缝）。`WebWindow._Place` 早就带了这个判据，
    ;   这边此前漏了，正好对上「首次 Alt+Z 偶尔只出任务栏」。
    ;   本机窗口最小尺寸是 675×450（逻辑 450×300 @150%），200×120 足够宽裕。
    static MinStableW := 200
    static MinStableH := 120

    static _MeasureStable(hwnd, &w, &h) {
        prevW := -1, prevH := -1, same := 0
        loop 60 {
            try
                WinGetPos(&_, &_, &w, &h, "ahk_id " . hwnd)
            catch
                return false
            if (w >= this.MinStableW && h >= this.MinStableH && w = prevW && h = prevH) {
                if (++same >= 2)
                    return true
            } else {
                same := 0
            }
            prevW := w, prevH := h
            Sleep 10
        }
        ; 超时：只有量到一个「像样的」尺寸才让调用方继续定位。
        ; 否则宁可不动（窗口停在 AHK 默认落点），也别把它摆到屏幕外。
        return (w >= this.MinStableW && h >= this.MinStableH)
    }

    ; ═══ 兜底落点（区域不可用时才用）═══

    ; 移到默认落点：贴主屏工作区右上角。
    ; 区域不可用通常是「屏幕太小、记录区放不下最小高度」—— 这时窗口总得有个地方待。
    static _MoveToDefault(g, ghwnd) {
        w := 0, h := 0
        if !this._MeasureStable(ghwnd, &w, &h)
            return
        rect := this._DefaultRect(w, h)
        ; 同样用 WinMove（物理像素），只设位置不设尺寸 —— 尺寸交给 AHK 按 DPI 决定
        WinMove(rect.x, rect.y, , , "ahk_id " . ghwnd)
    }

    ; 默认落点坐标：贴主屏工作区右上角 —— 右边距 Config.PlaceRight、顶边距 Config.PlaceTop。
    ;
    ; ⚠ 尺寸必须按窗口的「实际」值算 —— A_ScreenWidth 是物理像素，而窗口实际宽含 DPI
    ;   放大后的控件与边框（本机约 711），远大于 450 这样的逻辑值。
    ; ⚠ 用 MonitorGetWorkArea 而非 A_ScreenWidth / A_ScreenHeight：后者是全屏尺寸，
    ;   多屏时也只反映主屏。
    static _DefaultRect(winW, winH) {
        MonitorGetWorkArea(MonitorGetPrimary(), &wkLeft, &wkTop, &wkRight, &wkBottom)
        posX := wkRight - winW - Config.PlaceRight
        posY := wkTop + Config.PlaceTop
        ; 窗口比工作区还大（或边距过大）时兜底，免得落到负坐标、跑到屏幕外
        if (posX < wkLeft + 10)
            posX := wkLeft + 10
        if (posY < wkTop + 10)
            posY := wkTop + 10
        if (posY + winH > wkBottom)
            posY := wkBottom - winH - 10
        return {x: posX, y: posY}
    }
}
