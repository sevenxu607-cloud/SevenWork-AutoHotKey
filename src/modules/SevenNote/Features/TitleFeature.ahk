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

        dlg := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "日期标签")
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
        btnOk := dlg.AddButton("Default x14 y76 w100", "确定")
        btnClear := dlg.AddButton("x122 y76 w100", "清除")
        btnCancel := dlg.AddButton("x230 y76 w100", "取消")
        dlg.AddText("x14 y112 w340 c" . p.dim
            , "示例：2026-09-19-机器学习`n标签会写进文件名，黑曜石里一眼可见")

        OnSubmit(*) {
            newTag := NoteStoreService.SanitizeTag(edit.Value)
            dlg.Destroy()
            TitleFeature._Apply(date, currentTag, newTag)
        }

        OnClear(*) {
            dlg.Destroy()
            if (currentTag != "")
                TitleFeature._Apply(date, currentTag, "")
        }

        btnOk.OnEvent("Click", OnSubmit)
        btnClear.OnEvent("Click", OnClear)
        btnCancel.OnEvent("Click", (*) => dlg.Destroy())
        dlg.OnEvent("Escape", (*) => dlg.Destroy())
        dlg.OnEvent("Close", (*) => dlg.Destroy())

        edit.Focus()
        dlg.Show("w380 h150")
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
            EventBus.Emit("Title.Changed"
                , {date: date, tag: newTag})
        } else {
            MsgBox("重命名失败，请检查文件是否被其他程序占用"
                , "错误", 48)
        }
    }
}
