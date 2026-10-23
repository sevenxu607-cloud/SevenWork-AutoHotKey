#Requires AutoHotkey v2.0
; ======================================================================
;  FontService
;  Moved verbatim from SevenNote.ahk (Phase 2); behavior unchanged.
; ======================================================================

; ─── FontService：字体应用 ───
class FontService {
    ; 字体档位（用户 2026-10-23 定：删掉仿宋 / 微软雅黑 / 黑体，只留这四款）。
    ; ⚠ 删除的必须是最**末尾**的几项：`[Appearance] FontIndex` 存的是数组下标，
    ;   往中间删会把用户当前字体顶成另一个 —— 要再删就先确认没人选过后面那几档。
    static Fonts := ["楷体", "华文行楷", "华文新魏", "方正舒体"]
    static Sizes := [12, 14, 16, 18, 20]

    static _curFont := 1
    static _curSize := 2
    static _loading := false

    static GetName() => this.Fonts[this._curFont]
    static GetSize() => this.Sizes[this._curSize]

    static NextFont() {
        this._curFont++
        if (this._curFont > this.Fonts.Length)
            this._curFont := 1
        this.Apply()
    }

    static BiggerSize() {
        if (this._curSize < this.Sizes.Length) {
            this._curSize++
            this.Apply()
        }
    }

    static SmallerSize() {
        if (this._curSize > 1) {
            this._curSize--
            this.Apply()
        }
    }

    ; 应用字体 / 字号。
    ;
    ; ⚠ v2.9 起编辑区是 WebView2：不再往 RichEdit 灌 CHARFORMAT ——
    ;   `State.GetEd()` 恒为 0，从前那段 `if !hwndEd return` 会让整个函数**直接返回**，
    ;   连配置都不写、事件都不发。于是「用户在旧版调过的字号」永远停在配置文件里，
    ;   新编辑区一直用 CSS 的默认 14pt —— 这正是「文字格式和以前割裂」的一半来源。
    ;   现在取值由 HostBridge.NoteHostTheme() 带给前端（--sw-ed-font / --sw-ed-size），
    ;   这里只负责：落配置 + 广播 Font.Changed（订阅者按新字号重刷页面）。
    static Apply() {
        if !this._loading
            this.SaveToConfig()

        EventBus.Emit("Font.Changed", {name: this.GetName(), size: this.GetSize()})
    }

    static SaveToConfig() {
        ConfigService.Write("Appearance", "FontIndex", this._curFont)
        ConfigService.Write("Appearance", "FontSizeIndex", this._curSize)
    }

    static LoadFromConfig() {
        this._loading := true
        fi := ConfigService.ReadInt("Appearance", "FontIndex", 1)
        if (fi < 1 || fi > this.Fonts.Length)
            fi := 1
        this._curFont := fi
        si := ConfigService.ReadInt("Appearance", "FontSizeIndex", 2)
        if (si < 1 || si > this.Sizes.Length)
            si := 2
        this._curSize := si
        this.Apply()
        this._loading := false
    }
}
