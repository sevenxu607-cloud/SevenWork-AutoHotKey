#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════════
;  RectMath —— 纯几何能力（平台能力层）
; ═══════════════════════════════════════════════════════════════════════════
; 只接收数字与矩形，不读 Config / State / 屏幕，不发事件，不搬窗口。
; 所有坐标与尺寸一律是**物理像素**，与 WinGetPos / WinMove 同一单位。
;
; 矩形约定：
;   Rect      {x, y, w, h}                 x / y 为左上角
;   Frame     {l, t, r, b}                 外框比可见边界多出来的那圈不可见边框
;   WorkArea  {x, y, w, h}                 显示器工作区
;
; 这里不判断「窗口在不在 / 可不可见 / 在哪个屏」—— 那些归 WindowProbe。
; 需要窗口上下文的调用方先量好，再把数字交给这里。

class RectMath {
    ; ─── 可见边界 → 物理外框 ─────────────────────────────────────────────

    static Physical(note) {
        return {x: note.x + note.frame.l
            , y: note.y + note.frame.t
            , w: Max(note.w + note.frame.r - note.frame.l, 1)
            , h: Max(note.h + note.frame.b - note.frame.t, 1)}
    }

    ; ─── 贴角 ────────────────────────────────────────────────────────────
    ; 贴工作区**右上角**；offsetRight / offsetTop 为物理像素边距。
    ; WebWindow 的 place: "topright" 用它（面板类浮层的可选落点）。
    static TopRightRect(workArea, w, h, offsetRight := 0, offsetTop := 0) {
        if !this._ValidRect(workArea)
            return ""
        if !(IsNumber(w) && IsNumber(h) && w > 0 && h > 0)
            return ""
        x := workArea.x + workArea.w - w - offsetRight
        y := workArea.y + offsetTop
        if (x < workArea.x + 10)
            x := workArea.x + 10
        if (y < workArea.y + 10)
            y := workArea.y + 10
        return {x: x, y: y}
    }

    static _ValidRect(rect) {
        return IsObject(rect)
            && rect.HasProp("x") && rect.HasProp("y")
            && rect.HasProp("w") && rect.HasProp("h")
            && IsNumber(rect.x) && IsNumber(rect.y)
            && IsNumber(rect.w) && IsNumber(rect.h)
            && rect.w > 0 && rect.h > 0
    }

}
