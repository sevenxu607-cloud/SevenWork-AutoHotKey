#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════════
;  PowerShellFeature —— Alt+C 呼出 PowerShell
; ═══════════════════════════════════════════════════════════════════════════
; 终端固定落「辅助区」（ZoneService）；不再让笔记窗口让位 / 堆叠。
; 认窗靠窗口标题（SevenWork PowerShell），与终端自己的 profile 无关。
class PowerShellFeature {
    static _initialized := false
    static _powershellPath := A_WinDir . "\System32\WindowsPowerShell\v1.0\powershell.exe"
    static _windowTitle := "SevenWork PowerShell"
    ; Phase 6 改名前的窗口标题：升级后仍能认回旧终端，避免「Alt+C 又开一个」
    static _legacyWindowTitle := "SevenNote PowerShell"

    static Init() {
        if (this._initialized)
            return
        ; 热键由 LauncherModule.GetHotkeys() 交给 HotkeyRouter；Feature 不再自注册。
        this._initialized := true
    }

    static Toggle() {
        hwnd := this._FindPowerShellHwnd()
        if (hwnd = 0) {
            this._LaunchPowerShell()
            return
        }

        ; ⚠ 必须同时看「可见」：WinHide 之后 GetForegroundWindow 仍指着那个隐藏窗口
        ;   （本机实测 1.2s 后依然如此），只看 WinActive 会判定成「在前台 → 再藏一次」，
        ;   于是按了没反应、再也呼不出来。DeepSeekFeature.Toggle 是同一处。
        if (this._IsVisible(hwnd) && WinActive("ahk_id " . hwnd)) {
            WinHide("ahk_id " . hwnd)
            return
        }

        this._ShowAndFocus(hwnd)
    }

    ; 窗口此刻是否真的在屏幕上（WinHide 过 = false）。
    ; ⚠ 别用 IsIconic 组合来判断这里的「在显示」—— 那是判断最小化的写法：
    ;   本窗口只会被 WinHide 藏起来，不会被最小化，看 IsWindowVisible 一个就够。
    static _IsVisible(hwnd) => !!DllCall("IsWindowVisible", "ptr", hwnd, "int")

    static _FindPowerShellHwnd() {
        detectHidden := A_DetectHiddenWindows
        DetectHiddenWindows(true)
        try {
            ids := WinGetList(this._windowTitle)
            if !ids.Length
                ids := WinGetList(this._legacyWindowTitle)
            return ids.Length ? ids[1] : 0
        } finally {
            DetectHiddenWindows(detectHidden = "On")
        }
    }

    static _ShowAndFocus(hwnd) {
        WinShow("ahk_id " . hwnd)
        ; ⚠ WinShow 之后必须再 WinRestore：窗口被 WinHide 藏起来后，宿主可能把自己
        ;   标记成「最小化」，而 WinShow 不解除最小化，用户看到的就是「窗口没回来」。
        ;   浏览器（Chromium）实测必现，终端留着这行也无害 —— 兜底就该一直有。
        WinRestore("ahk_id " . hwnd)
        WinActivate("ahk_id " . hwnd)
        try {
            WinSetAlwaysOnTop("On", "ahk_id " . hwnd)
        }
        this._PlaceToAux(hwnd)
    }

    ; 落辅助区：锚定左上、保留终端自己的尺寸（高度归 Windows Terminal 的 profile）。
    ; 不改高度 —— WT profile 对高度的语义比 WinMove 硬设更可靠；位置对齐才是关键。
    static _PlaceToAux(hwnd) {
        res := ZoneService.Place(hwnd, "aux", {fill: false, allowHidden: false})
        if !res.ok && res.reason != "not-placeable" && res.reason != "minimized" && res.reason != "no-zone"
            LogError("终端落辅助区失败：" . res.reason)
    }

    ; 启动目录：默认 D 盘根目录，可在 _config.ini 的 [Paths] PowerShellStartDir 覆盖
    ; 若目标目录不存在（如无 D 盘），依次回退到用户主目录、A_MyDocuments，避免启动失败
    ; 注：AHK v2 没有 A_UserProfile 内置变量，用户主目录需取自 USERPROFILE 环境变量
    static _StartDir() {
        dir := ConfigService.Read("Paths", "PowerShellStartDir")
        if (dir = "")
            dir := "D:\"
        if !DirExist(dir)
            dir := EnvGet("USERPROFILE")
        if !DirExist(dir)
            dir := A_MyDocuments
        return dir
    }

    static _LaunchPowerShell() {
        if !FileExist(this._powershellPath) {
            MsgBox("未检测到 Windows PowerShell，无法使用 Alt+C 启动。", Config.AppName, "Icon!")
            return
        }

        try {
            command := "$Host.UI.RawUI.WindowTitle = '" . this._windowTitle . "'"
            ; ⚠ Run 的第三个参数只能留空，绝不能传 "Hide"。
            ;
            ; 本机 HKCU:\Console\%%Startup 里 DelegateTerminal = {00000000}「让 Windows 决定」，
            ; 实际落到 Windows Terminal：正常启动时 conhost 会把控制台交接给它，于是终端是
            ; 你配好的那个 —— Windows PowerShell profile、星空背景图、One Half Dark。
            ; 但 **隐藏着启动，这次交接就不会发生**，终端退回由 conhost 自己承载，顶着注册表
            ; 默认值出现：WindowSize = 120x50（实测 1488x1256）、conhost 的级联落点、
            ; 配色变成 powershell.exe 子键里的 ColorTable05 = #012456 经典蓝。
            ; 症状就是「终端背景失灵、位置大小不对」。
            ;
            ; 实测（AHK 探针，同样两条命令各启动一次、取窗口家族差集）：
            ;   Run(cmd, dir)          → CASCADIA_HOSTING_WINDOW_CLASS（Windows Terminal）
            ;   Run(cmd, dir, "Hide")  → ConsoleWindowClass（conhost）
            ;
            ; 代价：终端会带着「Windows PowerShell」旧标题先露一脸，等 PowerShell 进程把标题
            ; 设好、我们再轮询到它才归位。这一步的观感只能由 Windows Terminal 自己承载 ——
            ; 藏窗口绕过它，等于把整台终端换掉。
            Run('"' . this._powershellPath . '" -NoLogo -NoExit -Command "' . command . '"', this._StartDir())
        } catch as err {
            MsgBox("启动 PowerShell 失败：`n" . err.Message, Config.AppName, "Icon!")
            return
        }

        ; 轮询要密：终端进程起来约 0.7s，每一档的等待都会叠进「按了没反应」的那段空白。
        deadline := A_TickCount + 15000
        while (A_TickCount < deadline) {
            hwnd := this._FindPowerShellHwnd()
            if (hwnd != 0) {
                this._ShowAndFocus(hwnd)
                return
            }
            Sleep(20)
        }

        hwnd := this._FindPowerShellHwnd()
        if (hwnd != 0) {
            this._ShowAndFocus(hwnd)
        } else {
            MsgBox("PowerShell 已启动，但未能找到它的窗口。", Config.AppName, "Icon!")
        }
    }
}
