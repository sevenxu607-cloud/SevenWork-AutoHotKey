#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════════
;  AppSlotFeature —— Alt+Shift+1/2/3：启动或唤出槽位应用，并落到配置区域
; ═══════════════════════════════════════════════════════════════════════════
; 语义与 Alt+C / Alt+X 一致（2026-10-20 用户选定的 A 方案）：
;   窗口没开        → 启动命令行，轮询到窗口后落区
;   开着且在前台    → WinHide（再按一次收起来）
;   开着但不在前台  → 激活 + 落区（不藏，否则「按一下就没」）
;   已最小化 / 收起 → 恢复 + 激活 + 落区
;
; ⚠ 认窗只能按 exe 文件名（CommandLine.ExeOf）：
;   多实例只取面积最大的主窗；UWP（ApplicationFrameHost）与提权窗口不支持。
; ⚠ 同步轮询最长 15 秒：与 Alt+C 同一条路，期间热键线程被占。
; ⚠ 不弹模态框：空槽位 / 启动失败 / 找不到窗口都用 ToolTip —— 模态框会挡住热键。
;
; ⚠ 最小化 / 收起必须认回（2026-10-26 修）：
;   以前 _FindWindow 把 IsIconic 与不可见的窗口全部跳过，于是「用户把 Obsidian
;   最小化之后再按 Alt+Shift+1」找不到窗口 → 走 Run(cmd)。单实例程序收到第二次
;   启动请求会**新开一扇窗**（新的渲染进程），看起来就是「不是呼出，而是又开了一个」。
;   现在按「显示 → 最小化 → 收起」三级取主窗，Run 只在真的没有窗口时才走。

class AppSlotFeature {
    static LaunchTimeout := 15000
    static PollInterval := 25

    ; ToolTip 的清除定时器（照 FolderWindowFeature 的写法：闭包存在字段上才停得掉）。
    static _tipTimer := ""

    static Run(slot) {
        cmd := AppSlotService.Get(slot)
        if (cmd = "") {
            this.Tip(AppSlotService.HotkeyLabel(slot)
                . " 还没设置应用 —— 已打开面板，选「应用」页")
            EventBus.Emit("Panel.OpenRequested", {moduleId: "Launcher"})
            return
        }

        exe := AppSlotService.ExeOf(cmd)
        if (exe = "") {
            this.Tip("槽位命令里找不到 exe（第一段必须是 exe）：`n" . cmd)
            return
        }

        zone := AppSlotService.GetZone(slot)

        hwnd := this._FindWindow(exe)
        if hwnd {
            if (this._IsVisible(hwnd) && WinActive("ahk_id " . hwnd)) {
                try WinHide("ahk_id " . hwnd)
                return
            }
            this._ShowAndFocus(hwnd, zone)
            return
        }

        this._Launch(cmd, exe, zone)
    }

    static _Launch(cmd, exe, zone) {
        try Run(cmd)
        catch as e {
            LogError("应用槽位启动失败：" . cmd . " —— " . e.Message)
            this.Tip("启动失败：" . exe)
            return
        }

        deadline := A_TickCount + this.LaunchTimeout
        while (A_TickCount < deadline) {
            hwnd := this._FindWindow(exe)
            if hwnd {
                this._ShowAndFocus(hwnd, zone)
                return
            }
            Sleep(this.PollInterval)
        }

        LogError("应用槽位未在 " . this.LaunchTimeout . "ms 内找到窗口：" . exe)
        this.Tip(exe . " 已启动，但没找到窗口")
    }

    ; 按 exe 文件名找**主窗口**，三级取：
    ;   ① 显示中（可见 + 未最小化 + 有标题 + 尺寸正常）—— 按面积取最大
    ;   ② 已最小化（有标题 + 还原尺寸正常）—— 按还原面积取最大
    ;   ③ 已收起（隐藏、有标题、非辅助窗类）—— 按还原面积取最大
    ;
    ; ⚠ 不能只取第一个：Everything 的搜索窗 / Obsidian 的弹窗 / Chromium 辅助窗
    ;   都可能排在主窗口前面；填满它们等于没摆主窗口（用户看到的就是「没反应」）。
    ; ⚠ 二级 / 三级是 2026-10-26 补的：漏掉它们就会「最小化后再按热键 = 又开一扇窗」。
    ; ⚠ 三级只认主窗口类：Chromium / Electron 的隐藏合成窗（Chrome_WidgetWin_0、
    ;   Base_PowerMessageWindow）一旦 WinShow 就是一块没有标题、没有正常关闭入口的
    ;   巨大空白窗（2026-10-24 踩过）。它们本来也没有标题，两道筛子都过得去才认。
    static _FindWindow(exe) {
        detectOld := A_DetectHiddenWindows
        DetectHiddenWindows(true)
        try {
            ids := WinGetList("ahk_exe " . exe)
            if !ids.Length
                return 0

            shown := 0, shownArea := -1      ; ① 正在屏幕上
            mini := 0, miniArea := -1        ; ② 最小化在任务栏
            hid := 0, hidArea := -1          ; ③ 被收起（WinHide / 托盘）

            for h in ids {
                ; 桌面 / 任务栏不是应用主窗口；若槽位误填 explorer.exe，
                ; 不能把整个桌面当成目标窗口来填满。
                cls := WinGetClass("ahk_id " . h)
                if (cls = "Progman" || cls = "WorkerW" || cls = "Shell_TrayWnd")
                    continue

                ; 标题非空先筛掉大半：Chromium 合成窗、IME / MSCTFIME 窗都没有真标题。
                if (WinGetTitle("ahk_id " . h) = "")
                    continue

                visible := !!DllCall("IsWindowVisible", "ptr", h, "int")
                iconic := !!DllCall("IsIconic", "ptr", h, "int")

                ; 当前尺寸只能在「显示且未最小化」时量：最小化窗口 WinGetPos 给的是
                ; 屏幕外停放位与退化尺寸（实测 Obsidian 158x26），隐藏窗口直接抛。
                ; 另两种读 GetWindowPlacement 的还原尺寸（rcNormalPosition）。
                if (visible && !iconic) {
                    try
                        WinGetPos(, , &w, &hh, "ahk_id " . h)
                    catch
                        continue
                } else if !this._RestoreSize(h, &w, &hh)
                    continue

                ; 0×0 / 启动残影不参与「最大窗口」评选。
                if (w < 120 || hh < 80)
                    continue
                area := w * hh

                if (visible && !iconic) {
                    if (area > shownArea) {
                        shown := h
                        shownArea := area
                    }
                } else if iconic {
                    if (area > miniArea) {
                        mini := h
                        miniArea := area
                    }
                } else {
                    if this._IsHelperClass(cls)
                        continue
                    if (area > hidArea) {
                        hid := h
                        hidArea := area
                    }
                }
            }

            if shown
                return shown
            if mini
                return mini
            return hid
        } finally {
            DetectHiddenWindows(detectOld)
        }
    }

    ; 窗口的「还原尺寸」（GetWindowPlacement 的 rcNormalPosition），单位与 WinGetPos 相同。
    ; ⚠ 最小化 / 隐藏的窗口量不到当前尺寸，只能读这个；它只用于判断
    ;   「是不是一扇正常大小的窗口」，不参与摆位（摆位一律交给 ZoneService）。
    ; WINDOWPLACEMENT 在 64 位下 44 字节：length(0) flags(4) showCmd(8)
    ;   ptMin(12,16) ptMax(20,24) rcNormal(28,32,36,40)。
    static _RestoreSize(hwnd, &w, &h) {
        buf := Buffer(44, 0)
        NumPut("uint", 44, buf, 0)
        if !DllCall("GetWindowPlacement", "ptr", hwnd, "ptr", buf)
            return false
        w := NumGet(buf, 36, "int") - NumGet(buf, 28, "int")
        h := NumGet(buf, 40, "int") - NumGet(buf, 32, "int")
        return true
    }

    ; Chromium / Win32 的辅助窗口类名 —— 它们不该被当成主窗、更不该被 WinShow。
    ; IME 类虽然叫 "Default IME"，但尺寸为 0，正常已被上一关筛掉，这里再挡一次。
    static _IsHelperClass(cls) {
        return cls = "Chrome_WidgetWin_0"
            || cls = "Chrome_MessageWindow"
            || cls = "Base_PowerMessageWindow"
            || cls = "Intermediate D3D Window"
            || cls = "MSCTFIME UI"
            || cls = "IME"
            || cls = "tooltips_class32"
            || cls = "#32770"
    }

    static _ShowAndFocus(hwnd, zone) {
        ; 三步都不能省：WinShow 从隐藏态回来；ShowWindow(SW_RESTORE) 解除最小化；
        ; WinActivate 把前台要回来。失败就是「窗口已经没了」，不刷日志。
        ; ⚠ 恢复最小化用 ShowWindow(SW_RESTORE=9)，不用 WinRestore：后者按 WinTitle
        ;   匹配，窗口刚 WinShow / 句柄正忙时会抛 Target window not found（DeepSeek 踩过）；
        ;   对「只是被 WinHide」的窗口调它同样会抛（隐藏窗口不在默认搜索范围）。
        try WinShow("ahk_id " . hwnd)
        if DllCall("user32\IsIconic", "ptr", hwnd, "int")
            try DllCall("user32\ShowWindow", "ptr", hwnd, "int", 9)

        ; ⚠ 必须等它真的「可见且未最小化」再摆：ShowWindow 是异步的，Obsidian 这类
        ;   Electron 程序要几十到几百毫秒才退出最小化。这期间 PlacementExecutor 会
        ;   判 minimized 直接放弃，而 ZoneService.Watch 的第一轮复核又会因此停掉 ——
        ;   实测表现是「窗口回来了，但停在它自己记住的位置 1,7,1183,1066，没落工作区」。
        this._WaitReady(hwnd)

        try WinActivate("ahk_id " . hwnd)

        ; 工作区应用填满区域：保留上次尺寸会让 Everything / Obsidian 越区。
        ; 有些程序会在露面后恢复自己的尺寸，8 秒内每 500ms 复核一次。
        this._PlaceNow(hwnd, zone)
        ZoneService.Watch(hwnd, zone, true)

        ; 登记到区域注册表：Alt+Shift+V 时按这一条把窗口摆回原区域。
        ZoneService.Register(hwnd, "app", zone, true)
    }

    ; 等窗口「可见且未最小化」。超时返回 false —— 调用方照常往下走，
    ; ZoneService.Watch 还会在 8 秒内复核；这里只负责把「刚恢复的那一瞬」挡掉。
    static _WaitReady(hwnd, timeoutMs := 1500) {
        deadline := A_TickCount + timeoutMs
        while (A_TickCount < deadline) {
            if this._IsVisible(hwnd) && !DllCall("user32\IsIconic", "ptr", hwnd, "int")
                return true
            Sleep(20)
        }
        return false
    }

    static _PlaceNow(hwnd, zone) {
        res := ZoneService.Place(hwnd, zone, {fill: true, allowHidden: false})
        if !res.ok && res.reason != "not-placeable" && res.reason != "minimized" && res.reason != "no-zone"
            LogError("应用槽位落区失败：" . zone . " —— " . res.reason)
    }

    static _IsVisible(hwnd) => !!DllCall("IsWindowVisible", "ptr", hwnd, "int")

    ; 轻量确认：ToolTip 在鼠标旁闪一下。
    static Tip(msg, ms := 1800) {
        try ToolTip(msg)
        this._StopTipTimer()
        timerFn := () => this._ClearTip()
        this._tipTimer := timerFn
        SetTimer(timerFn, -ms)
    }

    static _StopTipTimer() {
        timerFn := this._tipTimer
        this._tipTimer := ""
        if IsObject(timerFn)
            try SetTimer(timerFn, 0)
    }

    static _ClearTip(*) {
        this._tipTimer := ""
        try ToolTip()
    }
}
