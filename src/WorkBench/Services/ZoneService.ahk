#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════════
;  ZoneService —— 工作台的三区域（平台服务）
; ═══════════════════════════════════════════════════════════════════════════
; 只做四件事：
;   ① 读 [Vision] 的尺寸配置，交给 ZoneMath 算三块可见矩形；
;   ② 把一个 hwnd 摆进某个区域（可见矩形 → 物理外框 → PlacementExecutor）；
;   ③ 记住「谁在哪个区」，供 Alt+Shift+V 恢复布局；
;   ④ 给面板提供区域名 / 中文标签的映射。
;
; ⚠ 区域不能住在 modules\Vision：笔记 / 应用 / 文件都要用，而跨模块零调用
;   （.clinerules/02）。所以几何与状态留在平台层，Vision 模块只是用户入口
;   —— 与 ThemeService / ThemeModule 同一套分工。
; ⚠ 不读 State、不认识任何业务模块；失败一律返回 {ok:false, reason}。
;
; 配置（_config.ini）：
;   [Vision]
;   AuxW=772     辅助区宽（物理像素）
;   AuxH=1020    辅助区高（物理像素）
;   Right=15     右缘离工作区右边的距离
;   Gap=6        区域之间的缝
;   Margin=10    工作区左 / 上边距
;
; ⚠ 区域按**可见边界**算（与 .clinerules 里 DockGap 的口径一致）；摆放时才用
;   WindowProbe.InvisibleFrame + RectMath.Physical 转成 WinMove 认的外框。

class ZoneService {
    static Section := "Vision"

    ; hwnd → {role, zone, fill}；只记工作窗口，不记面板 / 提示词库这类浮层。
    static _registered := Map()

    ; ─── 配置 ────────────────────────────────────────────────────────────
    static AuxW() => ConfigService.ReadInt(this.Section, "AuxW", 772)
    static AuxH() => ConfigService.ReadInt(this.Section, "AuxH", 1020)

    ; ─── 区域矩形 ────────────────────────────────────────────────────────
    ; zone 收内部 key（record / aux / work）或中文标签（记录区 / 辅助区 / 工作区）。
    ; 返回可见边界 {x, y, w, h}（物理像素）；未知区域 / 放不下返回 ""。
    static Rect(zone, monitorIdx := 0) {
        key := this.KeyOf(zone)
        if (key = "")
            return ""
        r := this.All(monitorIdx)
        if !r.ok
            return ""
        return r.%key%
    }

    ; 三块一起取（探针 / 面板预览）。返回 ZoneMath 的结果。
    static All(monitorIdx := 0) {
        area := WindowProbe.PrimaryWorkArea(monitorIdx)
        return ZoneMath.FromAux(area, this.AuxW(), this.AuxH(), this._Opts())
    }

    ; ─── 摆放 ────────────────────────────────────────────────────────────
    ; opts {fill, allowHidden}；缺省 fill=false、allowHidden=false。
    ;   fill=true   目标尺寸 = 区域尺寸（笔记用）；
    ;   fill=false  只对齐区域左上角，保留窗口当前尺寸（应用 / 文件用）。
    ; 返回 {ok:true, rect:物理外框} | {ok:false, reason}
    static Place(hwnd, zone, opts := "") {
        if !hwnd
            return {ok: false, reason: "bad-hwnd"}

        rect := this.Rect(zone)
        if !IsObject(rect)
            return {ok: false, reason: "no-zone"}

        fill := this._Opt(opts, "fill", false)
        allowHidden := this._Opt(opts, "allowHidden", false)

        w := rect.w, h := rect.h
        if !fill {
            cur := WindowProbe.RectOf(hwnd, true)
            if IsObject(cur) {
                w := cur.w, h := cur.h
            }
        }
        ; 锚定时也不能超出区域：窗口比区域还大就按区域缩
        if (w > rect.w)
            w := rect.w
        if (h > rect.h)
            h := rect.h

        frame := WindowProbe.InvisibleFrame(hwnd)
        phys := RectMath.Physical({x: rect.x, y: rect.y, w: w, h: h, frame: frame})
        res := PlacementExecutor.Move(hwnd, phys, allowHidden)
        if res.ok
            return {ok: true, rect: phys}
        return res
    }

    ; ─── 居中（小对话框用）─────────────────────────────────────────────
    ; 把窗口放在区域中心、**不缩放**（标签对话框这类小窗）。比区域大时溢出，
    ; 再夹到工作区。allowHidden 缺省 true：调用方通常在 Show("Hide") 之后定位。
    static CenterIn(hwnd, zone, allowHidden := true) {
        if !hwnd
            return {ok: false, reason: "bad-hwnd"}
        z := this.Rect(zone)
        if !IsObject(z)
            return {ok: false, reason: "no-zone"}
        cur := WindowProbe.RectOf(hwnd, true)
        if !IsObject(cur)
            return {ok: false, reason: "no-window"}

        area := WindowProbe.PrimaryWorkArea()
        x := z.x + (z.w - cur.w) // 2
        y := z.y + (z.h - cur.h) // 2
        if (x < area.x + 10)
            x := area.x + 10
        if (x + cur.w > area.x + area.w - 10)
            x := area.x + area.w - 10 - cur.w
        if (y < area.y + 10)
            y := area.y + 10
        if (y + cur.h > area.y + area.h - 10)
            y := area.y + area.h - 10 - cur.h

        res := PlacementExecutor.Move(hwnd
            , {x: x, y: y, w: cur.w, h: cur.h}, allowHidden)
        if res.ok
            return {ok: true, rect: {x: x, y: y, w: cur.w, h: cur.h}}
        return res
    }

    ; ─── 注册表：谁在哪个区 ──────────────────────────────────────────────
    ; role 只用于日志 / 将来辨认（"note" / "app:1" / "file:2"），不参与几何。
    static Register(hwnd, role, zone, fill := false) {
        if !hwnd
            return false
        key := this.KeyOf(zone)
        if (key = "")
            return false
        this._registered[hwnd] := {role: role, zone: key, fill: fill}
        return true
    }

    static Unregister(hwnd) {
        if this._registered.Has(hwnd)
            this._registered.Delete(hwnd)
    }

    ; 把注册表里仍然存在的窗口按各自区域重摆一次（Alt+Shift+V）。
    ; 只摆已开窗口，不启动程序、不激活窗口。
    ; 返回 {ok, applied, skipped, failed}；ok = 没有失败项。
    static ApplyLayout() {
        applied := 0, skipped := 0, failed := 0
        for hwnd, info in this._registered {
            ; 用 IsWindow 而不是 WinExist：WinExist 默认忽略隐藏窗口，
            ; 而笔记收起后 hwnd 仍在、Alt+Shift+V 应该还能把它摆回记录区。
            if !DllCall("user32\IsWindow", "ptr", hwnd, "int") {
                skipped += 1
                continue
            }
            res := this.Place(hwnd, info.zone, {fill: info.fill, allowHidden: true})
            if res.ok
                applied += 1
            else if res.reason = "minimized"
                skipped += 1
            else
                failed += 1
        }
        return {ok: failed = 0, applied: applied, skipped: skipped, failed: failed}
    }

    ; ─── 标签映射 ────────────────────────────────────────────────────────
    static KeyOf(zone) {
        z := Trim("" . zone)
        if (z = "record" || z = "记录区")
            return "record"
        if (z = "aux" || z = "辅助区")
            return "aux"
        if (z = "work" || z = "工作区")
            return "work"
        return ""
    }

    ; 面板 select 的候选值（值即显示）。
    static Options() => ["记录区", "辅助区", "工作区"]

    ; ─── 内部 ────────────────────────────────────────────────────────────
    static _Opt(opts, name, default) {
        if IsObject(opts) && opts.HasProp(name)
            return opts.%name%
        return default
    }

    ; 交给 ZoneMath 的参数。min* 是逻辑单位，按 DPI 换成物理像素：
    ; 文档里的 450x300 是笔记窗口的最小尺寸，320x200 是"还看得出是扇窗"的下限。
    static _Opts() {
        dpi := A_ScreenDPI
        return {
            right:       ConfigService.ReadInt(this.Section, "Right", 15)
          , gap:         ConfigService.ReadInt(this.Section, "Gap", 6)
          , margin:      ConfigService.ReadInt(this.Section, "Margin", 10)
          , minWorkW:    320 * dpi // 96
          , minRecordH:  300 * dpi // 96
          , minAuxW:     200 * dpi // 96
          , minAuxH:     120 * dpi // 96
        }
    }
}
