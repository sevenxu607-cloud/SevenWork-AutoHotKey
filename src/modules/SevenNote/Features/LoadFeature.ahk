#Requires AutoHotkey v2.0
; ======================================================================
;  LoadFeature.ahk
;  Moved verbatim from SevenNote.ahk (Phase 2); behavior unchanged.
; ======================================================================

class LoadFeature {
    static Load() {
        return this.LoadDate(FormatTime(, "yyyy-MM-dd"))
    }

    ; 切日期 / 跳转 / 首次载入都走这里。
    ;
    ; ⚠ 调用方负责先把当前这篇落盘（`NoteSessionService.Save()`）——
    ;   Feature 之间不互相调用，这里不替别人做决定。
    ; 返回 true 才代表「屏幕上现在真的是这一天」。日期提交、正文推送、
    ; 读文件失败这些事全在 `NoteSessionService.Open()` 里按顺序做完了 ——
    ; 从前这里先 `State.SetDate()` 再推正文，推失败就成了「标题是新的一天、
    ; 屏幕是旧内容」，接着一保存就把旧正文写到新日期上。
    static LoadDate(date) {
        r := NoteSessionService.Open(date)
        if !r.ok {
            LogError("载入 " . date . " 失败：" . r.reason)
            return false
        }
        return true
    }
}

