#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════════
;  FolderWindowFeature —— Alt+1/2/3 呼出 · 隐藏文件夹窗口
; ═══════════════════════════════════════════════════════════════════════════
; 语义（与 Alt+C / Alt+X 一致，2026-10-20 用户选定的 A 方案）：
;   窗口没开        → 打开该目录
;   开着且在前台    → WinHide 藏起来（从任务栏消失）
;   开着但不在前台  → 只激活，不藏（否则「按一下就没」，人会找不到）
;   已经藏着        → WinShow + WinRestore + 激活
;
; ⚠ 定位不用窗口标题：资源管理器标题 = 文件夹名，重名 / 本地化都不可靠。
;   走 ExplorerProbe 读 Shell.Application 里的真实路径。
; ⚠ 本 Feature 不写任何配置：槽位读写全在 FolderSlotService。
; ⚠ 反斜杠在 AHK 字符串里不是转义符（只有反引号是）。

class FolderWindowFeature {
    ; 打开后等窗口露面的上限。资源管理器冷启动在机械盘上实测能到 1~2 秒，
    ; 留到 4 秒；每次都 Sleep(25) 轮询，别用大间隔 —— 那是「按了没反应」的空白期。
    static LaunchTimeout := 4000
    static PollInterval := 25

    ; ToolTip 的关闭定时器（照 PromptWindowFeature 的写法：闭包存在字段上才停得掉）。
    static _tipTimer := ""

    ; ═══ 主入口（热键直接指过来，参数是槽位号）═══

    static Toggle(slot) {
        state := FolderSlotService.GetUsable(slot)
        if (!state.ok) {
            this._ReportUnusable(slot, state)
            return
        }
        path := state.path

        hwnd := ExplorerProbe.FindFor(path)
        if !hwnd {
            this._Launch(slot, path)
            return
        }

        ; ⚠ 必须同时看「可见」与「前台」：WinHide 之后 GetForegroundWindow 仍可能
        ;   指着那个隐藏窗口（本机实测），只看 WinActive 会判定成「在前台 → 再藏一次」，
        ;   表现是「按了没反应、再也呼不出来」。与 PowerShellFeature.Toggle 同一条教训。
        if (this._IsVisible(hwnd) && WinActive("ahk_id " . hwnd)) {
            this._Hide(hwnd)
            return
        }

        this._ShowAndFocus(hwnd)
        this._PlaceBySlot(slot, hwnd)
    }

    ; ═══ 打开 ═══

    static _Launch(slot, path) {
        ; Run(目录) 走 ShellExecute → **尊重用户的「在同一窗口中打开每个文件夹」设置**。
        ; 不用 `explorer.exe /n` —— 那会无视用户偏好强行开新窗口，用久了满屏资源管理器。
        try Run(path)
        catch as e {
            LogError("打开文件夹失败：" . path . " —— " . e.Message)
            this.Tip("打开失败：" . path)
            return
        }

        ; 轮询到窗口出现并激活。少了这一步，首次按下会「没反应」——
        ; 新窗口出来时前台可能还在原来那个程序上（尤其从全屏程序里呼出时）。
        deadline := A_TickCount + this.LaunchTimeout
        while (A_TickCount < deadline) {
            hwnd := ExplorerProbe.FindFor(path)
            if hwnd {
                this._ShowAndFocus(hwnd)
                this._PlaceBySlot(slot, hwnd)
                return
            }
            Sleep(this.PollInterval)
        }

        ; 超时不弹模态框：窗口多半已经开了，只是这一轮 COM 没查到（路径被重定向 /
        ; 网络盘慢）。记日志就够 —— 用户再按一次会走「已开 → 激活」分支，
        ; 而模态框会挡住热键、只能手动关。
        LogError("文件夹窗口未在 " . this.LaunchTimeout . "ms 内出现：" . path)
    }

    ; ═══ 显示 / 隐藏 ═══

    static _ShowAndFocus(hwnd) {
        ; ⚠ 三步都不能省：
        ;   WinShow     —— 从 WinHide 的隐藏态回来；
        ;   WinRestore  —— WinShow 不解除最小化，被藏过的窗口宿主可能已标成最小化，
        ;                  少了这一步用户看到的就是「窗口没回来」（浏览器 / 终端实测必现）；
        ;   WinActivate —— 把前台要回来。
        ; 窗口可能在轮询期间被用户关掉，三个调用都用 try —— 失败就是「已经没了」，
        ; 不是需要惊动用户的错误。
        try WinShow("ahk_id " . hwnd)
        try WinRestore("ahk_id " . hwnd)
        try WinActivate("ahk_id " . hwnd)
    }

    static _Hide(hwnd) {
        try WinHide("ahk_id " . hwnd)
        catch as e
            LogError("隐藏文件夹窗口失败：" . e.Message)
    }

    ; 按槽位配置把资源管理器窗口摆到区域（**填满**工作区，避免保留上次尺寸越区）。
    ; ⚠ Explorer 会在露面后套用自己的位置/尺寸，第一次 WinMove 可能被它盖回去；
    ;   8 秒内每 500ms 复核一次，窗口被收起 / 最小化就停止。
    static _PlaceBySlot(slot, hwnd) {
        zone := FolderSlotService.GetZone(slot)
        this._PlaceNow(hwnd, zone)
        ZoneService.Watch(hwnd, zone, true)
        ; 即使这次没摆成也登记：恢复布局时会再试一次。
        ZoneService.Register(hwnd, "file", zone, true)
    }

    static _PlaceNow(hwnd, zone) {
        res := ZoneService.Place(hwnd, zone, {fill: true, allowHidden: false})
        if !res.ok && res.reason != "not-placeable" && res.reason != "minimized" && res.reason != "no-zone"
            LogError("文件夹窗口落区失败：" . zone . " —— " . res.reason)
    }

    static _IsVisible(hwnd) => !!DllCall("IsWindowVisible", "ptr", hwnd, "int")

    ; ═══ 槽位没配好 ═══

    ; 不弹模态框（会挡住热键、只能手动关）：ToolTip 说明 + 请平台把面板开到文件夹页。
    ; 平台类不在这里直接调 —— 发事件，WebPanelUI 订阅后负责打开。
    static _ReportUnusable(slot, state) {
        label := FolderSlotService.HotkeyLabel(slot)
        if (state.reason = "missing")
            this.Tip(label . " 指向的目录不存在：`n" . state.path)
        else
            this.Tip(label . " 还没设置文件夹 —— 已打开面板，选「文件」页")
        EventBus.Emit("Panel.OpenRequested", {moduleId: "Folders"})
    }

    ; 轻量确认：ToolTip 在鼠标旁闪一下。
    ; **公开**：同模块的 ConvertFeature（Alt+M 转 Markdown）也用它 —— 一份实现、一个
    ; 定时器字段，两条提示就不会互相清掉（各持一个定时器才会：先弹的那条到点会把
    ; 后一条一起清）。
    ; ⚠ 仍与 PromptWindowFeature._Tip 是两份实现（跨模块，Text 模块本轮不动）：
    ;   Text 与 Folders 的提示若在 ms 内先后出现，先弹的会把后一条清掉。只影响观感、
    ;   不影响功能，真要合并得抽一个公共 ToolTip 能力。
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
