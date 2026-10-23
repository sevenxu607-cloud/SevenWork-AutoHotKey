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

    ; 应用字体 / 字号：只落配置 + 广播 Font.Changed。
    ; 页面那边的取值由 HostBridge.NoteHostTheme() 带过去（--sw-ed-font / --sw-ed-size）。
    ; ⚠ 这里**不要**加「编辑区没就绪就 return」的守卫 —— 编辑区已交给 WebView2，
    ;   那种守卫会让配置写不进去、页面永远停在默认 14pt。
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
