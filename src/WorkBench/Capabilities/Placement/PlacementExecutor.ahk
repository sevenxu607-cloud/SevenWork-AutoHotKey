#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════════
;  PlacementExecutor —— 唯一搬窗口的出口（平台能力层）
; ═══════════════════════════════════════════════════════════════════════════
; 平台只算矩形，模块把「要搬哪扇窗」交给这里执行：
;   · Move 只收物理像素矩形，不读 Config / State，不发事件；
;   · 失败返回 {ok:false, reason}，由调用方决定是否记录 / 回退；
;   · allowHidden = true 供「Show("Hide") 后的笔记窗口」使用，
;     缺省 false 时要求窗口可见且未最小化。
;
; ⚠ 为什么不能在平台层直接跨模块 WinMove：
;   那会把窗口生命周期和业务模块搅在一起；Move 事件已经带了完整矩形，
;   各模块只需在自己的订阅者里调用这一个执行器。

class PlacementExecutor {
    ; 返回 {ok:true} 或 {ok:false, reason}
    ; reason: bad-input / bad-rect / not-placeable / not-found / minimized / move-failed
    static Move(hwnd, rect, allowHidden := false) {
        if !hwnd || !IsObject(rect)
            return {ok: false, reason: "bad-input"}
        if !(rect.HasProp("x") && rect.HasProp("y")
            && rect.HasProp("w") && rect.HasProp("h"))
            return {ok: false, reason: "bad-rect"}
        if !(IsNumber(rect.x) && IsNumber(rect.y)
            && IsNumber(rect.w) && IsNumber(rect.h))
            return {ok: false, reason: "bad-rect"}
        if (rect.w <= 0 || rect.h <= 0)
            return {ok: false, reason: "bad-rect"}

        ; 可见窗口先过「可见 + 未最小化」的闸；隐藏笔记由 allowHidden 放行。
        if !allowHidden && !WindowProbe.IsPlaceable(hwnd)
            return {ok: false, reason: "not-placeable"}

        detectOld := A_DetectHiddenWindows
        DetectHiddenWindows(true)
        try {
            if !WinExist("ahk_id " . hwnd)
                return {ok: false, reason: "not-found"}
            ; 最小化窗口的位置是停放位，别搬 —— 即使 allowHidden 也不碰。
            if DllCall("IsIconic", "ptr", hwnd, "int")
                return {ok: false, reason: "minimized"}
            ; 最大化窗口 WinMove 不生效：先恢复成普通窗口再搬。
            ; 用 ShowWindow(SW_RESTORE=9) 而不是 WinRestore：后者按 WinTitle 匹配，
            ; 在「隐藏 → 可见」那一瞬可能匹配不到。
            if DllCall("IsZoomed", "ptr", hwnd, "int")
                try DllCall("user32\ShowWindow", "ptr", hwnd, "int", 9)
            WinMove(rect.x, rect.y, rect.w, rect.h, "ahk_id " . hwnd)
        } catch as e {
            return {ok: false, reason: "move-failed", error: e.Message}
        } finally {
            DetectHiddenWindows(detectOld)
        }
        return {ok: true}
    }
}
