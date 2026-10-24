#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════════
;  ZoneMath —— 三区域几何（平台能力层）
; ═══════════════════════════════════════════════════════════════════════════
; 把一个工作区切成三块固定区域：
;
;     ┌──────────────────────────┬──────────────────┐
;     │                          │     记录区        │  记录区：辅助区正上方
;     │        工作区            ├──────────────────┤
;     │   （左侧剩余矩形）        │     辅助区        │  辅助区：右下角
;     └──────────────────────────┴──────────────────┘
;
; 口径与现有布局一致：
;   · 辅助区贴工作区右下角：右缘离 right、底边贴工作区底；
;   · 记录区与辅助区**同宽同 x**，顶边离工作区顶 margin，底边离辅助区顶 gap；
;   · 工作区是左侧剩余矩形（不含缝）：x 离工作区左 margin，右到辅助区左缘减 gap。
;
; 只收数字与矩形，不读 Config / State、不查屏幕、不搬窗口。
; 所有坐标与尺寸一律是**物理像素**，且按**可见边界**算（不含 DWM 那圈不可见边框）。
; 把可见矩形转成 WinMove 认的外框，由调用方用 WindowProbe.InvisibleFrame +
; RectMath.Physical 完成 —— 这一步需要 hwnd，不属于纯几何。
;
; 小屏兜底：
;   · 辅助区太高 → 缩到「记录区还能保住 minRecordH」；
;   · 辅助区太宽 → 缩到「工作区还能保住 minWorkW」；
;   · 缩到 minAuxW / minAuxH 仍放不下 → {ok:false, reason:"no-fit"}。

class ZoneMath {
    ; workArea {x, y, w, h}     显示器工作区（物理像素）
    ; auxW/auxH                 想要的辅助区尺寸（物理像素）
    ; opts {right, gap, margin, minWorkW, minRecordH, minAuxW, minAuxH}
    ;   全部物理像素；right / gap / margin 可以为 0，min* 必须 > 0
    ;
    ; 返回 {ok:true, aux, record, work} 或 {ok:false, reason}
    static FromAux(workArea, auxW, auxH, opts) {
        if !this._ValidRect(workArea)
            return {ok: false, reason: "bad-work-area"}
        if !this._ValidOpts(opts)
            return {ok: false, reason: "bad-opts"}
        if !(IsNumber(auxW) && IsNumber(auxH) && auxW > 0 && auxH > 0)
            return {ok: false, reason: "bad-aux-size"}

        ; 可用宽度 = 工作区去掉左 margin 与右 right
        innerW := workArea.w - opts.margin - opts.right
        if (innerW <= 0)
            return {ok: false, reason: "no-fit"}

        ; 宽度不能把工作区挤到 minWorkW 以下
        maxAuxW := innerW - opts.gap - opts.minWorkW
        if (maxAuxW < opts.minAuxW)
            return {ok: false, reason: "no-fit"}
        if (auxW > maxAuxW)
            auxW := maxAuxW

        ; 高度不能把记录区挤到 minRecordH 以下（辅助区底边贴工作区底）
        maxAuxH := workArea.h - opts.margin - opts.gap - opts.minRecordH
        if (maxAuxH < opts.minAuxH)
            return {ok: false, reason: "no-fit"}
        if (auxH > maxAuxH)
            auxH := maxAuxH

        auxX := workArea.x + workArea.w - auxW - opts.right
        auxY := workArea.y + workArea.h - auxH
        ; 兜底：别越过左 / 上 margin（窗口比工作区还大时才会命中）
        if (auxX < workArea.x + opts.margin)
            auxX := workArea.x + opts.margin
        if (auxY < workArea.y + opts.margin)
            auxY := workArea.y + opts.margin

        recordY := workArea.y + opts.margin
        recordH := auxY - opts.gap - recordY
        if (recordH < opts.minRecordH)
            return {ok: false, reason: "no-fit"}

        workX := workArea.x + opts.margin
        workW := auxX - opts.gap - workX
        if (workW < opts.minWorkW)
            return {ok: false, reason: "no-fit"}

        return {
            ok: true,
            aux:    {x: auxX, y: auxY, w: auxW, h: auxH},
            record: {x: auxX, y: recordY, w: auxW, h: recordH},
            work:   {x: workX, y: recordY, w: workW, h: workArea.h - opts.margin}
        }
    }

    ; ─── 入参校验 ────────────────────────────────────────────────────────
    static _ValidRect(rect) {
        return IsObject(rect)
            && rect.HasProp("x") && rect.HasProp("y")
            && rect.HasProp("w") && rect.HasProp("h")
            && IsNumber(rect.x) && IsNumber(rect.y)
            && IsNumber(rect.w) && IsNumber(rect.h)
            && rect.w > 0 && rect.h > 0
    }

    static _ValidOpts(opts) {
        if !IsObject(opts)
            return false
        for name in ["right", "gap", "margin", "minWorkW", "minRecordH", "minAuxW", "minAuxH"] {
            if !opts.HasProp(name) || !IsNumber(opts.%name%)
                return false
        }
        return opts.right >= 0 && opts.gap >= 0 && opts.margin >= 0
            && opts.minWorkW > 0 && opts.minRecordH > 0
            && opts.minAuxW > 0 && opts.minAuxH > 0
    }
}
