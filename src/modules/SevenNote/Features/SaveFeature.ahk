#Requires AutoHotkey v2.0
; ======================================================================
;  SaveFeature.ahk
;  Moved verbatim from SevenNote.ahk (Phase 2); behavior unchanged.
; ======================================================================

class SaveFeature {
    static Init() {
        ; ⚠ 不再订阅 `Window.BeforeHide`：保存已经提前到 `WindowFeature.Hide()` 的第一步，
        ;   在那里**存不住就不收起**。再挂一个订阅只会把同一篇存两遍，
        ;   第二次的结果还会把状态栏刚写的「已保存」冲成「无改动」。
        EventBus.On("Save.Requested", (*) => SaveFeature.Save())
    }

    ; 落盘：从编辑器取 Markdown → 写 .md。
    ;
    ; v2.9 起 **Markdown 是母版**，RTF 退出保存路径（原文只在 `ExportFeature` 类
    ; 的导出链上还用它，本仓库已无）。所以这里不再碰 RichEdit、不再调 Pandoc。
    ;
    ; 真正的判断（有没有载入、页面在不在、空笔记、内容没变）全在
    ; `NoteSessionService.Save()` 里，结果的广播也在那里 —— 这里只留两个入口：
    ; 热键 `Ctrl+S` 与 `Save.Requested` / `Window.BeforeHide` 事件。
    ;
    ; 返回同一个结果对象：调用方（切日期 / 退出）据此决定还要不要继续 ——
    ; 「事件发出去了」不等于「已经存好了」。
    static Save() => NoteSessionService.Save()

    ; 取编辑器里的存储态 Markdown；取不到返回空串（调用方据此跳过这次保存）。
    static Take() => NoteSessionService.TakeMarkdown()
}

