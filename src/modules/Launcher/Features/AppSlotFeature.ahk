#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════════
;  AppSlotFeature —— Alt+Shift+1/2/3：启动或唤出槽位应用，并落到配置区域
; ═══════════════════════════════════════════════════════════════════════════
; 语义与 Alt+C / Alt+X 一致（2026-10-20 用户选定的 A 方案）：
;   窗口没开        → 启动命令行，轮询到窗口后落区
;   开着且在前台    → WinHide（再按一次收起来）
;   开着但不在前台  → 激活 + 落区（不藏，否则「按一下就没」）
;   已最小化        → WinRestore + 激活 + 落区
;
; ⚠ 认窗只能按 exe 文件名（CommandLine.ExeOf）：
;   多实例只取第一个窗口；UWP（ApplicationFrameHost）与提权窗口不支持。
; ⚠ 同步轮询最长 8 秒：与 Alt+C 的 15 秒同一条路，期间热键线程被占。
; ⚠ 不弹模态框：空槽位 / 启动失败 / 找不到窗口都用 ToolTip —— 模态框会挡住热键。

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

    ; 按 exe 文件名找**主窗口**：可见、未最小化、有标题里面积最大的那个。
    ; ⚠ 不能只取第一个：Everything 的搜索窗 / Obsidian 的弹窗 / Chromium 辅助窗
    ;   都可能排在主窗口前面；填满它们等于没摆主窗口（用户看到的就是「没反应」）。
    static _FindWindow(exe) {
        detectOld := A_DetectHiddenWindows
        DetectHiddenWindows(true)
        try {
            ids := WinGetList("ahk_exe " . exe)
            if !ids.Length
                return 0
            first := 0
            best := 0, bestArea := -1
            for h in ids {
                if !first
                    first := h
                if !DllCall("IsWindowVisible", "ptr", h, "int")
                    || DllCall("IsIconic", "ptr", h, "int")
                    continue
                if (WinGetTitle("ahk_id " . h) = "")
                    continue
                try
                    WinGetPos(, , &w, &hh, "ahk_id " . h)
                catch
                    continue
                area := w * hh
                if (area > bestArea) {
                    best := h
                    bestArea := area
                }
            }
            return best ? best : first
        } finally {
            DetectHiddenWindows(detectOld)
        }
    }

    static _ShowAndFocus(hwnd, zone) {
        ; 三步都不能省：WinShow 从隐藏态回来；WinRestore 解除最小化；
        ; WinActivate 把前台要回来。失败就是「窗口已经没了」，不刷日志。
        try WinShow("ahk_id " . hwnd)
        try WinRestore("ahk_id " . hwnd)
        try WinActivate("ahk_id " . hwnd)

        ; 工作区应用填满区域：保留上次尺寸会让 Everything / Obsidian 越区。
        ; 有些程序会在露面后恢复自己的尺寸，8 秒内每 500ms 复核一次。
        this._PlaceNow(hwnd, zone)
        ZoneService.Watch(hwnd, zone, true)

        ; 登记到区域注册表：Alt+Shift+V 时按这一条把窗口摆回原区域。
        ZoneService.Register(hwnd, "app", zone, true)
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
