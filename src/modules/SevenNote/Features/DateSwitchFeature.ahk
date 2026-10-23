#Requires AutoHotkey v2.0
; ======================================================================
;  DateSwitchFeature.ahk
;  Moved verbatim from SevenNote.ahk (Phase 2); behavior unchanged.
; ======================================================================

class DateSwitchFeature {
    static Switch(offset) {
        curDate := NoteSessionService.GetDate()
        if (curDate = "")
            return false

        ; ⚠ 保存不成功就不许切走。
        ;   从前这里只发一个 `Save.Requested` 就走 —— 事件是「通知」不是「结果」，
        ;   保存失败照样换文档：用户看到新的一天，丢掉的是刚写的那一天。
        ;   recoverable = 当前根本没有可丢的内容（冷启动 / 页面还没挂），那种放行。
        saved := NoteSessionService.Save()
        if !saved.ok && !(saved.HasProp("recoverable") && saved.recoverable)
            return false

        ymd := StrReplace(curDate, "-", "")
        target := DateAdd(ymd, offset, "Days")
        targetStr := FormatTime(target, "yyyy-MM-dd")

        ; 换文档统一由 NoteSessionService 负责：读文件 → 推编辑器 → 确认后才提交日期。
        ; 它失败时日期一动不动，屏幕上还是原来那一篇。
        if !NoteSessionService.Open(targetStr).ok
            return false
        EventBus.Emit("Date.Switched", {date: targetStr})
        return true
    }
}
