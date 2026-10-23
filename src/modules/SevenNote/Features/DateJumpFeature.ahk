#Requires AutoHotkey v2.0
; ======================================================================
;  DateJumpFeature.ahk
;  Moved verbatim from SevenNote.ahk (Phase 2); behavior unchanged.
; ======================================================================

class DateJumpFeature {
    ; 别的 Feature（今日）要跳日期时发这个事件 —— Feature 之间不互相调用
    static Init() {
        EventBus.On("Date.JumpRequested", (d) => this.JumpTo(d.date))
    }

    static ShowDialog() {
        ; 这是笔记模块自己的对话框，标题跟着模块显示名走（不借用工作台的 Config.AppName）
        winTitle := SevenNoteModule.Title . " · 搜索跳转"
        if WinExist(winTitle . " ahk_class AutoHotkeyGUI") {
            WinActivate(winTitle . " ahk_class AutoHotkeyGUI")
            return
        }

        dlg := Gui("+Resize +AlwaysOnTop", winTitle)
        dlg.SetFont("s11", "Microsoft YaHei")
        ; 配色跟着平台主题走（对话框是短命的：打开时取一次当期色板即可，
        ; 开着的时候按 Alt+T 不追 —— 下次打开就是新色）
        p := ThemeService.Palette()
        dlg.BackColor := p.win

        dlg.AddText("x14 y16 w60", "搜索：")
        searchEdit := dlg.AddEdit("x72 y12 w480 h26")
        searchEdit.SetFont("s11", "Microsoft YaHei")
        ; Edit 不吃 BackColor，走 WM_CTLCOLOREDIT 登记（见 UiPaint.EditColors）
        UiPaint.EditColors(searchEdit.Hwnd, p.codeBg, p.text)

        dlg.AddText("x14 y46 w560 c" . p.dim
            , "支持模糊搜索：日期（2026-09）或标签（机器学习），空格分隔多条件")

        lv := dlg.AddListView("x14 y74 w538 h360", ["日期", "标签"])
        lv.ModifyCol(1, 130)
        lv.ModifyCol(2, 400)
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

        JumpToSelected(*) {
            row := lv.GetNext()
            if (row = 0)
                return
            dateStr := lv.GetText(row, 1)
            if (dateStr = "")
                return
            dlg.Destroy()
            DateJumpFeature.JumpTo(dateStr)
        }

        lv.OnEvent("DoubleClick", JumpToSelected)

        btnClose := dlg.AddButton("x472 y444 w80", "关闭")
        btnClose.OnEvent("Click", (*) => dlg.Destroy())

        HotIfWinActive(winTitle)
        Hotkey("Enter", (*) => JumpToSelected(), "On")
        Hotkey("NumpadEnter", (*) => JumpToSelected(), "On")
        Hotkey("Escape", (*) => dlg.Destroy(), "On")
        HotIf()
        dlg.OnEvent("Close", (*) => (
            HotIfWinActive(winTitle),
            Hotkey("Enter", "Off"),
            Hotkey("NumpadEnter", "Off"),
            Hotkey("Escape", "Off"),
            HotIf(),
            dlg.Destroy()
        ))

        ApplyFilter("")
        dlg.Show("w560 h485")
        searchEdit.Focus()
    }

    static JumpTo(dateStr) {
        if (dateStr = "")
            return false

        ; ⚠ 与切日期同一条规矩：存不住就不跳。
        ;   从前只发 `Save.Requested` 就走，等于「保存失败也照样跳过去」。
        saved := NoteSessionService.Save()
        if !saved.ok && !(saved.HasProp("recoverable") && saved.recoverable)
            return false

        ; 换文档由 NoteSessionService 统一负责（读文件 → 推编辑器 → 提交日期）。
        ; 它失败时日期不变，屏幕上还是原来那一篇。
        if !NoteSessionService.Open(dateStr).ok
            return false
        EventBus.Emit("Date.Switched", {date: dateStr})
        return true
    }
}
