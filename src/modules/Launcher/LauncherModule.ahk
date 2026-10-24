#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════════
;  LauncherModule —— 外部程序模块生命周期
;  Phase 3 从组合根拆出：持有 PowerShell / DeepSeek 两个 Feature，
;  热键定义也归模块所有，注册仍由 WorkBench/HotkeyRouter 统一完成。
; ═══════════════════════════════════════════════════════════════════════════

class LauncherModule {
    static Id := "Launcher"
    static Name := "应用"
    static _initialized := false

    static Init() {
        if this._initialized
            return
        this._initialized := true

        ; Feature 只保留「启动 / 唤出 / 找到 hwnd」；落区由各自 Feature 调
        ; ZoneService（终端与浏览器都去辅助区），模块层不再订阅任何布局事件。
        PowerShellFeature.Init()
        DeepSeekFeature.Init()
    }

    ; 由 HotkeyRouter / WebPanelUI 聚合 —— 注册与 Alt+S 帮助共用这一份数据。
    static GetHotkeys() {
        return [
            {ctx: "global", key: "!c", group: "输入增强"
                , line: "   Alt+C            唤出 / 隐藏 PowerShell（落辅助区）"
                , fn: (*) => PowerShellFeature.Toggle()},
            {ctx: "global", key: "!x", group: "输入增强"
                , line: "   Alt+X            呼出 / 隐藏 DeepSeek 网页（落辅助区）"
                , fn: (*) => DeepSeekFeature.Toggle()}
        ]
    }

    static GetMetadata() {
        ; order = 40：面板里按七个应用排列（笔记 10 / 文本 20 / 文件 30 / 应用 40）。
        ; ⚠ 「输入增强」组内的条目也按模块 order 排，所以 Alt+C / Alt+X 会排在
        ;   CapsLock（60）之前 —— 这是统一命名的副作用，不是漏改排序。
        return {name: this.Name, desc: "PowerShell / DeepSeek · Alt+C", order: 40
            , hotkeys: this.GetHotkeys()}
    }
}
