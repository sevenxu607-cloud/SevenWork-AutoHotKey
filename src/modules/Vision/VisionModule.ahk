#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════════
;  VisionModule —— 视界（窗口管理的用户入口）
; ═══════════════════════════════════════════════════════════════════════════
; 三区域（记录 / 辅助 / 工作）与全部摆放逻辑都在平台 ZoneService；本模块只做：
;   · Alt+Shift+V：把注册表里还活着的窗口按各自区域重摆一遍（不启动程序）；
;   · 面板「视界」页：说明区域归属与暂缓的功能。
;
; ⚠ 一键启动 / 自定义布局暂缓（用户 2026-10-24 定）：没有执行入口之前不写入
;   布局字段，避免出现「改了没生效」的假设置。
; ⚠ 本模块不建窗口、不订阅事件；删掉它，区域几何与各窗口的落位仍然生效。

class VisionModule {
    static Id := "Vision"
    static Name := "视界"

    static _tipTimer := ""

    static Init() {
    }

    static GetHotkeys() {
        return [
            {ctx: "global", key: "!+v", group: "视界"
                , line: "   Alt+Shift+V      恢复布局（把已开窗口摆回各区域）"
                , fn: (*) => VisionModule.RestoreLayout()}
        ]
    }

    ; 只摆已开窗口：不启动、不激活、不读业务配置之外的任何东西。
    static RestoreLayout() {
        r := ZoneService.ApplyLayout()
        msg := "已恢复布局：" . r.applied . " 个窗口"
        if (r.skipped)
            msg .= " · 跳过 " . r.skipped
        if (r.failed)
            msg .= " · 失败 " . r.failed
        this.Tip(msg)
        if (r.failed)
            LogError("恢复布局有 " . r.failed . " 个窗口失败")
        return r
    }

    ; 面板设置页：只有说明，没有字段（一键启动暂缓，先不做假入口）。
    static GetSettingsSpec() {
        return {
            title: "视界",
            hint: "记录区 / 辅助区 / 工作区由平台统一管理："
                . "`n· 笔记固定落记录区（辅助区正上方）；"
                . "`n· 终端、浏览器落辅助区；"
                . "`n· 文件槽位与应用槽位按各自的「打开到」设置落区。"
                . "`n`nAlt+Shift+V 会把已开窗口按上次落位重新摆一遍（不启动程序）。"
                . "`n自定义布局与一键启动暂未启用。",
            fields: []
        }
    }

    static GetMetadata() {
        return {name: this.Name, desc: "三区域 · 恢复布局 Alt+Shift+V", order: 50
            , hotkeys: this.GetHotkeys()}
    }

    ; 轻量确认（视界不建窗口，只闪 ToolTip）。
    static Tip(msg, ms := 2000) {
        try ToolTip(msg)
        this._StopTipTimer()
        timerFn := () => this._ClearTip()
        this._tipTimer := timerFn
        SetTimer(timerFn, -ms)
    }

    static _StopTipTimer() {
        timerFn := this._tipTimer
        this._tipTimer := ""
        if IsObject(timerFn)
            try SetTimer(timerFn, 0)
    }

    static _ClearTip(*) {
        this._tipTimer := ""
        try ToolTip()
    }
}
