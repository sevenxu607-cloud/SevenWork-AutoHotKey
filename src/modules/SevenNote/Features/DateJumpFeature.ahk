#Requires AutoHotkey v2.0
; ======================================================================
;  DateJumpFeature.ahk
;  Moved verbatim from SevenNote.ahk (Phase 2); behavior unchanged.
; ======================================================================

class DateJumpFeature {
    ; 上一次 JumpTo 失败的原因（对话框留在屏幕上给用户看，不静默关掉）
    static _lastError := ""

    ; 别的 Feature（今日）要跳日期时发这个事件 —— Feature 之间不互相调用
    static Init() {
        EventBus.On("Date.JumpRequested", (d) => this.JumpTo(d.date))
    }

    static LastError() => this._lastError

    static ShowDialog() {
        ; 这是笔记模块自己的对话框，标题跟着模块显示名走（不借用工作台的 Config.AppName）
        winTitle := SevenNoteModule.Title . " · 搜索跳转"
        if WinExist(winTitle . " ahk_class AutoHotkeyGUI") {
            WinActivate(winTitle . " ahk_class AutoHotkeyGUI")
            return
        }

        ; 固定尺寸的搜索对话框：最大化 / 最小化都没有意义，
        ; 而且控件只按 aux 区域布局一次，最大化后会错位。
        dlg := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", winTitle)
        dlg.SetFont("s11", "Microsoft YaHei")
        ; 配色跟着平台主题走（对话框是短命的：打开时取一次当期色板即可，
        ; 开着的时候按 Alt+T 不追 —— 下次打开就是新色）
        p := ThemeService.Palette()
        dlg.BackColor := p.win

        ; 填满辅助区：窗口与控件都按区域的**逻辑**尺寸布局。
        ; 区域是物理像素；Gui 控件坐标收逻辑单位，必须按 A_ScreenDPI 换算。
        z := ZoneService.Rect("aux")
        lw := IsObject(z) ? z.w * 96 // A_ScreenDPI : 560
        lh := IsObject(z) ? z.h * 96 // A_ScreenDPI : 485
        lvH := Max(lh - 134, 180)

        dlg.AddText("x14 y16 w60", "搜索：")
        searchEdit := dlg.AddEdit("x72 y12 w" . (lw - 86) . " h26")
        searchEdit.SetFont("s11", "Microsoft YaHei")
        ; Edit 不吃 BackColor，走 WM_CTLCOLOREDIT 登记（见 UiPaint.EditColors）
        UiPaint.EditColors(searchEdit.Hwnd, p.codeBg, p.text)

        dlg.AddText("x14 y46 w" . (lw - 28) . " c" . p.dim
            , "支持模糊搜索：日期（2026-09）或标签（机器学习），空格分隔多条件")

        lv := dlg.AddListView("x14 y74 w" . (lw - 28) . " h" . lvH, ["日期", "标签"])
        lv.ModifyCol(1, 130)
        lv.ModifyCol(2, Max(lw - 28 - 130, 120))
        lv.SetFont("s10", "Microsoft YaHei")
        UiPaint.ListView(lv.Hwnd, p.codeBg, p.text)

        ; 标题栏 / 滚动条跟着主题明暗（Show 之前调，避免露面后再变一次）
        UiPaint.TitleBar(dlg.Hwnd, p.win, p.text)
        UiPaint.WindowTheme(dlg.Hwnd, p.dark)
        ; 玻璃背衬（只有玻璃主题给）：见 GlassPaint 的降级链
        UiPaint.Glass(dlg.Hwnd, p.style, p.win)

        allItems := NoteStoreService.ListAllTags()

        ApplyFilter(keyword) {
            lv.Delete()
            if (keyword = "") {
                for item in allItems
                    lv.Add(, item.date, item.tag)
                return
            }
            words := StrSplit(keyword, " ")
            for item in allItems {
                matched := true
                for w in words {
                    w := Trim(w)
                    if (w = "")
                        continue
                    if !(InStr(item.date, w) || InStr(item.tag, w)) {
                        matched := false
                        break
                    }
                }
                if matched
                    lv.Add(, item.date, item.tag)
            }
        }

        searchEdit.OnEvent("Change", (*) => ApplyFilter(Trim(searchEdit.Value)))

        ; 关闭对话框的唯一出口：先注销本次注册的上下文热键，再销毁窗口。
        ; ⚠ 关闭按钮 / Esc / 双击选择原来直接 Destroy，跳过了注销；
        ;   下次打开会累积旧热键，表现成「这个窗口怎么关都不对」。
        CloseDialog(*) {
            try {
                HotIfWinActive(winTitle)
                try Hotkey("Enter", "Off")
                try Hotkey("NumpadEnter", "Off")
                try Hotkey("Escape", "Off")
            } finally {
                HotIf()
                try dlg.Destroy()
            }
        }

        JumpToSelected(*) {
            row := lv.GetNext()
            if (row = 0)
                return
            dateStr := lv.GetText(row, 1)
            if (dateStr = "")
                return
            if DateJumpFeature.JumpTo(dateStr) {
                CloseDialog()
                return
            }
            ; 跳转失败时保留对话框并说明原因 —— 先 Destroy 会让用户只看到
            ; 「窗口关了、笔记没变」，完全不知道发生了什么。
            msg := "跳转失败：" . DateJumpFeature.LastError()
            try ToolTip(msg)
            SetTimer(() => ToolTip(), -4000)
            LogError(msg)
        }

        lv.OnEvent("DoubleClick", JumpToSelected)

        btnClose := dlg.AddButton("x" . (lw - 94) . " y" . (lh - 50) . " w80", "关闭")
        btnClose.OnEvent("Click", CloseDialog)

        HotIfWinActive(winTitle)
        Hotkey("Enter", (*) => JumpToSelected(), "On")
        Hotkey("NumpadEnter", (*) => JumpToSelected(), "On")
        Hotkey("Escape", (*) => CloseDialog(), "On")
        HotIf()
        dlg.OnEvent("Close", (*) => CloseDialog())

        ApplyFilter("")
        ; 填满辅助区：隐藏态定位，最后露面。
        ; Place(fill:true) 按区域可见尺寸转外框；控件已按同样的逻辑尺寸排好。
        dlg.Show("w" . lw . " h" . lh . " Hide")
        Sleep 30
        ZoneService.Place(dlg.Hwnd, "aux", {fill: true, allowHidden: true})
        dlg.Show()
        searchEdit.Focus()
    }

    static JumpTo(dateStr) {
        this._lastError := ""
        if (dateStr = "") {
            this._lastError := "日期为空"
            return false
        }

        ; ⚠ 与切日期同一条规矩：存不住就不跳。
        ;   从前只发 `Save.Requested` 就走，等于「保存失败也照样跳过去」。
        saved := NoteSessionService.Save()
        if !saved.ok && !(saved.HasProp("recoverable") && saved.recoverable) {
            this._lastError := "当前笔记保存失败："
                . (saved.HasProp("reason") ? saved.reason : "未知原因")
            return false
        }

        ; 换文档由 NoteSessionService 统一负责（读文件 → 推编辑器 → 提交日期）。
        ; 它失败时日期不变，屏幕上还是原来那一篇。
        opened := NoteSessionService.Open(dateStr)
        if !opened.ok {
            this._lastError := "打开日期失败："
                . (opened.HasProp("reason") ? opened.reason : "未知原因")
            return false
        }
        EventBus.Emit("Date.Switched", {date: dateStr})
        return true
    }
}
