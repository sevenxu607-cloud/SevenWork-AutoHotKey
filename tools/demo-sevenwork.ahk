#Requires AutoHotkey v2.0
#SingleInstance Off
; ═══════════════════════════════════════════════════════════════════════════
;  demo-sevenwork.ahk —— SevenWork UI 演示 / 自动验收驱动
; ═══════════════════════════════════════════════════════════════════════════
; 由 tools\demo-sevenwork.ps1 启动；必须与主应用是**两个进程**，否则
; HotIf 上下文热键收不到 Send（见 .clinerules/04）。
;
; 参数：
;   A_Args[1] Mode       Test / Demo
;   A_Args[2] DemoRoot   临时 Vault / 配置备份 / 报告目录
;   A_Args[3] RepoRoot   仓库根（定位 demo-obs.mjs）
;   A_Args[4] Record     Record / NoRecord
;   A_Args[5] AppPid     主应用 PID
; ═══════════════════════════════════════════════════════════════════════════

SetWorkingDir(A_ScriptDir)
SetTitleMatchMode(2)
SetKeyDelay(35, 80)
SetMouseDelay(20)
SendMode("Input")
; 主应用的上下文热键（Ctrl+G / Ctrl+N）由键盘钩子实现；驱动是独立进程，
; 用 SendLevel(1) 让它生成的按键能被主应用的 HotIf 热键接收。
SendLevel(1)
CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")

class DemoDriver {
    static Mode := "Test"
    static Root := ""
    static Repo := ""
    static Record := false
    static AppPid := 0
    static Chapter := ""
    static Pass := 0
    static Fail := 0
    static LogPath := ""
    static ObsLog := ""

    static Main() {
        args := A_Args
        this.Mode := args.Length >= 1 ? args[1] : "Test"
        this.Root := args.Length >= 2 ? args[2] : A_Temp . "\SevenWorkDemo"
        this.Repo := args.Length >= 3 ? args[3] : A_ScriptDir . "\.."
        this.Record := args.Length >= 4 ? (args[4] = "Record") : false
        this.AppPid := args.Length >= 5 ? Integer(args[5]) : 0
        this.LogPath := this.Root . "\driver.log"
        this.ObsLog := this.Root . "\obs-driver.log"
        if FileExist(this.LogPath)
            FileDelete(this.LogPath)
        this.Log("mode=" . this.Mode . " record=" . this.Record . " pid=" . this.AppPid)
        this.Caption("")

        try this.Run()
        catch as e {
            this.Fail += 1
            this.Log("EXCEPTION " . e.Message . " @ " . e.File . ":" . e.Line)
        }
        this.Log("RESULT pass=" . this.Pass . " fail=" . this.Fail)
        try ToolTip()
        ExitApp(this.Fail ? 1 : 0)
    }

    static Run() {
        if !ProcessExist(this.AppPid) {
            this.Assert(false, "主应用进程不存在")
            return
        }
        Sleep(2500)

        this.ChapterOne()
        this.ChapterTwo()
        this.ChapterThree()
        this.ChapterFour()
        this.ChapterFive()
        this.ChapterSix()
        this.ChapterSeven()
    }

    ; ─── 01 工作台 ───────────────────────────────────────────────────────
    static ChapterOne() {
        this.Begin("01-启动与工作台", "01 · 工作台与全部热键")
        Send("!s")
        hwnd := this.WaitWin("SevenWork · 工作台", 6000)
        this.Assert(hwnd != 0, "Alt+S 打开工作台")
        if hwnd {
            this.Activate(hwnd)
            Sleep(1500)
            this.Log("panel-active=" . (WinActive("ahk_id " . hwnd) ? 1 : 0) . " active-title=" . WinGetTitle("A"))
        }
        Send("!s")
        Sleep(700)
        this.Assert(!this.IsVisible(hwnd), "Alt+S 收起工作台")
        this.End()
    }

    ; ─── 02 笔记 ─────────────────────────────────────────────────────────
    static ChapterTwo() {
        this.Begin("02-笔记", "02 · 笔记、字体、日期跳转")
        Send("!z")
        hwnd := this.WaitWin("SevenNote ahk_class AutoHotkeyGUI", 6000)
        this.Assert(hwnd != 0, "Alt+Z 呼出笔记")
        if !hwnd {
            this.End()
            return
        }
        this.Activate(hwnd)
        Sleep(900)
        this.ClickInside(hwnd)
        Sleep(300)
        Send("^{End}")
        Send("{Enter}{Enter}")
        SendText("## 工作台演示追加")
        Send("{Enter}{Enter}")
        SendText("这是 SevenWork 的工作台演示：笔记会落到记录区，收起重开仍然保留。")
        Send("^s")
        Sleep(1000)
        this.Log("note-active-before-hotkeys=" . (WinActive("ahk_id " . hwnd) ? 1 : 0) . " active-title=" . WinGetTitle("A"))
        Send("!+t")
        Sleep(500)
        Send("!=")
        Sleep(500)
        this.Activate(hwnd)
        Send("^g")
        dlg := this.WaitWin("SevenNote · 搜索跳转", 5000)
        this.Assert(dlg != 0, "Ctrl+G 打开日期跳转")
        Sleep(900)
        Send("{Esc}")
        Sleep(700)
        this.Activate(hwnd)
        Send("!z")
        Sleep(900)
        this.Assert(!this.IsVisible(hwnd), "Alt+Z 收起笔记")
        ; Alt+Z 走 WindowFeature.Hide()，保存是收起的一部分；
        ; 在收起之后读文件，避免与页面异步保存抢跑。
        today := FormatTime(, "yyyy-MM-dd")
        notePath := this.Root . "\Vault\" . today . ".md"
        wrote := false
        loop 50 {
            text := FileExist(notePath) ? FileRead(notePath, "UTF-8") : ""
            if InStr(text, "工作台演示追加") {
                wrote := true
                break
            }
            Sleep(150)
        }
        this.Assert(wrote, "笔记内容写入文件")
        this.End()
    }

    ; ─── 03 文本 / 提示词 ────────────────────────────────────────────────
    static ChapterThree() {
        this.Begin("03-文本与提示词", "03 · 提示词库与新建")
        Send("!p")
        hwnd := this.WaitWin("SevenWork · 提示词库", 7000)
        this.Assert(hwnd != 0, "Alt+P 打开提示词库")
        if !hwnd {
            this.End()
            return
        }
        this.Activate(hwnd)
        Sleep(1200)
        this.Log("prompt-active-before-ctrl-n=" . (WinActive("ahk_id " . hwnd) ? 1 : 0) . " active-title=" . WinGetTitle("A"))
        Send("^n")
        edit := this.WaitWin("SevenWork · 新建提示词", 5000)
        this.Assert(edit != 0, "Ctrl+N 打开新建提示词")
        if edit {
            this.Activate(edit)
            Sleep(500)
            SendText("录屏演示提示词")
            Send("{Tab}")
            SendText("Work")
            Send("{Tab}")
            SendText("这是一条用于 SevenWork 工作台演示的提示词。")
            Send("^s")
            Sleep(1000)
            Send("{Esc}")
            Sleep(500)
        }
        promptPath := this.Root . "\Prompts\Work\录屏演示提示词.md"
        this.Assert(FileExist(promptPath), "提示词写入文件")
        this.Activate(hwnd)
        Send("{Esc}")
        Sleep(600)
        this.Assert(!this.IsVisible(hwnd), "Esc 收起提示词库")
        this.End()
    }

    ; ─── 04 文件 ─────────────────────────────────────────────────────────
    static ChapterFour() {
        this.Begin("04-文件槽位", "04 · 文件夹槽位")
        ; 上一次运行 / 用户留下的资源管理器会让 Alt+1 变成“收起”，
        ; 先关掉旧的 CabinetWClass 窗口，确保这一章真的打开演示目录。
        for h in WinGetList("ahk_class CabinetWClass") {
            try WinClose("ahk_id " . h)
        }
        Sleep(700)
        found := 0
        loop 3 {
            Send("!1")
            Sleep(1800)
            found := this.VisibleExplorer()
            if found
                break
        }
        this.Assert(found != 0, "Alt+1 打开资源管理器")
        Sleep(1200)
        this.End()
    }

    ; ─── 05 应用 / Obsidian ──────────────────────────────────────────────
    static ChapterFive() {
        this.Begin("05-应用-Obsidian", "05 · 应用槽位：Obsidian")
        Send("!+2")
        hwnd := this.WaitObsidian(15000)
        this.Assert(hwnd != 0, "Alt+Shift+2 打开 Obsidian")
        if hwnd {
            this.Activate(hwnd)
            ; 等 Obsidian 从启动图 / 空白过渡到真正的 Vault 界面。
            Sleep(4000)
            ; 打开演示 Vault 里的说明页，避免画面停在空白新标签页。
            Send("^o")
            Sleep(700)
            SendText("工作台演示")
            Sleep(800)
            Send("{Enter}")
            Sleep(1600)
            this.Log("obsidian-title=" . WinGetTitle("ahk_id " . hwnd))
        }
        this.End()
    }

    ; ─── 06 视界 ─────────────────────────────────────────────────────────
    static ChapterSix() {
        this.Begin("06-视界与布局", "06 · 三区域与恢复布局")
        Send("!+v")
        Sleep(1500)
        this.End()
    }

    ; ─── 07 退出 ─────────────────────────────────────────────────────────
    static ChapterSeven() {
        this.Begin("07-退出", "07 · 退出与清理")
        ; Obsidian 在前台时，某些配置会抢 Alt+Shift+S；先把笔记叫出来，
        ; 让 SevenWork 成为前台，再走全局退出热键。
        Send("!z")
        Sleep(900)
        Send("!+s")
        Sleep(1200)
        deadline := A_TickCount + 5000
        while (ProcessExist(this.AppPid) && A_TickCount < deadline)
            Sleep(100)
        this.Assert(!ProcessExist(this.AppPid), "Alt+Shift+S 退出应用")
        this.End()
    }


    ; ─── 通用 ────────────────────────────────────────────────────────────

    static Begin(name, title) {
        this.Chapter := name
        this.Log("== " . name . " ==")
        if (this.Mode = "Demo")
            this.Caption(title)
        if (this.Record)
            this.Obs("start")
        Sleep(400)
    }

    static End() {
        Sleep(500)
        if (this.Record) {
            this.Obs("snapshot", this.Chapter)
            this.Obs("stop", this.Chapter)
        }
        this.Caption("")
        Sleep(300)
    }

    static Obs(cmd, chapter := "") {
        if !this.Record
            return true
        script := this.Repo . "\tools\demo-obs.mjs"
        args := '"' . script . '" ' . cmd . ' --root "' . this.Root . '"'
        if ((cmd = "stop" || cmd = "snapshot") && chapter != "")
            args .= ' --chapter "' . chapter . '"'
        command := '"' . A_ComSpec . '" /d /c node ' . args . ' >> "' . this.ObsLog . '" 2>&1'
        try
            code := RunWait(command, , "Hide")
        catch as e {
            this.Fail += 1
            this.Log("OBS " . cmd . " EXCEPTION " . e.Message)
            return false
        }
        if (code != 0) {
            this.Fail += 1
            this.Log("OBS " . cmd . " failed code=" . code)
            return false
        }
        return true
    }

    static WaitWin(title, timeoutMs := 6000) {
        deadline := A_TickCount + timeoutMs
        loop {
            hwnd := WinExist(title)
            if hwnd
                return hwnd
            if (A_TickCount >= deadline)
                return 0
            Sleep(100)
        }
    }

    static WaitObsidian(timeoutMs) {
        deadline := A_TickCount + timeoutMs
        loop {
            for h in WinGetList("ahk_exe Obsidian.exe") {
                if !DllCall("IsWindowVisible", "ptr", h, "int")
                    continue
                if DllCall("IsIconic", "ptr", h, "int")
                    continue
                if (WinGetTitle("ahk_id " . h) = "")
                    continue
                return h
            }
            if (A_TickCount >= deadline)
                return 0
            Sleep(200)
        }
    }

    static VisibleExplorer() {
        for h in WinGetList("ahk_class CabinetWClass") {
            if !DllCall("IsWindowVisible", "ptr", h, "int")
                continue
            if DllCall("IsIconic", "ptr", h, "int")
                continue
            return h
        }
        return 0
    }

    static Activate(hwnd) {
        if !hwnd
            return false
        try WinActivate("ahk_id " . hwnd)
        Sleep(250)
        return true
    }

    static ClickInside(hwnd) {
        if !hwnd
            return false
        try WinGetPos(&x, &y, &w, &h, "ahk_id " . hwnd)
        catch
            return false
        Click(x + w // 2, y + h // 3)
        Sleep(250)
        return true
    }

    static IsVisible(hwnd) {
        if !hwnd
            return false
        return !!DllCall("IsWindowVisible", "ptr", hwnd, "int")
    }

    static Caption(text) {
        if (this.Mode != "Demo")
            return
        if (text = "") {
            try ToolTip()
        } else {
            try ToolTip(text, 20, 20, 1)
        }
    }

    static Assert(ok, message) {
        if ok {
            this.Pass += 1
            this.Log("PASS " . message)
        } else {
            this.Fail += 1
            this.Log("FAIL " . message)
        }
        return ok
    }

    static Log(text) {
        line := FormatTime(, "HH:mm:ss") . "  " . text . "`n"
        try FileAppend(line, this.LogPath, "UTF-8")
    }
}

DemoDriver.Main()

