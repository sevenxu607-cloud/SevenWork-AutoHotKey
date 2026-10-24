#Requires AutoHotkey v2.0
; ======================================================================
;  TitleFeature.ahk
;  Moved verbatim from SevenNote.ahk (Phase 2); behavior unchanged.
; ======================================================================

class TitleFeature {
    static ShowDialog() {
        date := State.GetDate()
        if (date = "")
            return

        mdPath := NoteStoreService.FindMd(date)
        currentTag := (mdPath != "")
            ? NoteStoreService.TagFromFileName(mdPath) : ""

        winTitle := "日期标签"
        dlg := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", winTitle)
        dlg.SetFont("s11", "Microsoft YaHei")
        ; 这一扇从前写死米黄 —— 深色主题下就是「白底 + 黑字」的孤岛
        p := ThemeService.Palette()
        dlg.BackColor := p.win
        UiPaint.TitleBar(dlg.Hwnd, p.win, p.text)
        UiPaint.WindowTheme(dlg.Hwnd, p.dark)
        UiPaint.Glass(dlg.Hwnd, p.style, p.win)
        dlg.AddText("x14 y12 w340 c" . p.text, "为 " . date . " 设置标签：")
        edit := dlg.AddEdit("x14 y38 w340 h26", currentTag)
        edit.SetFont("s11", "Microsoft YaHei")
        ; Edit 不吃 BackColor，走 WM_CTLCOLOREDIT 登记
        UiPaint.EditColors(edit.Hwnd, p.codeBg, p.text)
        ; 按钮改用 Text + SS_NOTIFY：原生 Button 的底色由系统画，深色窗口上是一块
        ; 白底黑字，与主题不协调。Text 继承窗口底色，文字用主题色；0x200 让文字垂直居中。
        btnOk := dlg.AddText("x14 y76 w100 h30 Center +0x300 Border c" . p.text, "确定")
        btnClear := dlg.AddText("x122 y76 w100 h30 Center +0x300 Border c" . p.text, "清除")
        btnCancel := dlg.AddText("x230 y76 w100 h30 Center +0x300 Border c" . p.text, "取消")
        dlg.AddText("x14 y112 w340 c" . p.dim
            , "示例：2026-09-19-机器学习`n标签会写进文件名，黑曜石里一眼可见")

        ; Enter / NumpadEnter：Text 不是原生按钮，默认回车不会触发「确定」。
        Cleanup() {
            HotIfWinActive(winTitle)
            for key in ["Enter", "NumpadEnter"]
                try Hotkey(key, "Off")
            HotIf()
        }
        CloseDlg(*) {
            Cleanup()
            try dlg.Destroy()
        }
        OnSubmit(*) {
            newTag := NoteStoreService.SanitizeTag(edit.Value)
            Cleanup()
            dlg.Destroy()
            TitleFeature._Apply(date, currentTag, newTag)
        }
        OnClear(*) {
            Cleanup()
            dlg.Destroy()
            if (currentTag != "")
                TitleFeature._Apply(date, currentTag, "")
        }

        btnOk.OnEvent("Click", OnSubmit)
        btnClear.OnEvent("Click", OnClear)
        btnCancel.OnEvent("Click", CloseDlg)
        dlg.OnEvent("Escape", CloseDlg)
        dlg.OnEvent("Close", CloseDlg)

        HotIfWinActive(winTitle)
        Hotkey("Enter", OnSubmit, "On")
        Hotkey("NumpadEnter", OnSubmit, "On")
        HotIf()

        edit.Focus()
        ; 位置：记录区中心（尺寸不变）。只移动默认呼出位置。
        dlg.Show("w380 h150 Hide")
        ZoneService.CenterIn(dlg.Hwnd, "record", true)
        dlg.Show()
    }

    static _Apply(date, oldTag, newTag) {
        if (oldTag = newTag)
            return
        ; ⚠ 改名之前必须确认正文已经落盘：文件正在被这次保存改写，
        ;   紧接着 Move 同一个文件会撞车（Windows 上表现为「拒绝访问」）。
        ;   而且保存失败时改名，等于把「没存上的那一篇」挂到一个新名字下。
        saved := NoteSessionService.Save()
        if !saved.ok && !(saved.HasProp("recoverable") && saved.recoverable)
            return

        if (newTag != "" && NoteStoreService.FindMd(date) = "") {
            EventBus.Emit("Error.Occurred"
                , {msg: "空笔记无法设标签，请先写内容"})
            return
        }
        if NoteStoreService.RenameWithTag(date, oldTag, newTag) {
            ; 改名会让磁盘文件名变掉 —— 会话里的路径必须跟着走，
            ; 否则下一次保存会按旧路径重新写出一份（同一天出现两个文件）
            NoteSessionService.SetPath(NoteStoreService.FindMd(date))
            EventBus.Emit("Title.Changed"
                , {date: date, tag: newTag})
        } else {
            MsgBox("重命名失败，请检查文件是否被其他程序占用"
                , "错误", 48)
        }
    }
}
