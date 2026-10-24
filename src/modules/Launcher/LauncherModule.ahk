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
                , fn: (*) => DeepSeekFeature.Toggle()},

            ; 应用槽位：热键固定，命令与区域在「应用」页配置。
            {ctx: "global", key: "!+1", group: "应用"
                , line: "   Alt+Shift+1      启动 / 唤出应用槽位 1"
                , fn: (*) => AppSlotFeature.Run(1)},
            {ctx: "global", key: "!+2", group: "应用"
                , line: "   Alt+Shift+2      启动 / 唤出应用槽位 2"
                , fn: (*) => AppSlotFeature.Run(2)},
            {ctx: "global", key: "!+3", group: "应用"
                , line: "   Alt+Shift+3      启动 / 唤出应用槽位 3"
                , fn: (*) => AppSlotFeature.Run(3)}
        ]
    }

    ; ─── 设置页：应用槽位 ─────────────────────────────────────────────
    ; 与文件模块完全对称：每槽「命令行 + 区域」，顺序 = SaveAll 的解析顺序。
    ; 值是完整命令行（第一段必须是 exe）；区域是中文标签。
    static GetSettingsSpec() {
        fields := []
        loop AppSlotService.Count {
            slot := A_Index
            fields.Push({
                key:   "Slot" . slot,
                label: AppSlotService.HotkeyLabel(slot) . " →",
                kind:  "text",
                value: AppSlotService.Get(slot),
                placeholder: '例：notepad.exe 或 "C:\...\app.exe" --arg（第一段必须是 exe）'
            })
            fields.Push({
                key:   "Slot" . slot . "Zone",
                label: "   打开到 →",
                kind:  "select",
                value: AppSlotService.GetZone(slot),
                options: ZoneService.Options()
            })
        }
        return {
            title: "应用槽位",
            hint: "热键固定为 Alt+Shift+1/2/3；槽位里填完整命令行（第一段是 exe），再选落区。"
                . "`nAlt+C / Alt+X 仍是 PowerShell / DeepSeek 的固定快捷键，不听槽位配置。"
                . "`n不支持 cmd /c start、UWP 应用与提权窗口。",
            fields: fields,
            apply: (values) => AppSlotService.SaveAll(values)
        }
    }

    static GetMetadata() {
        ; order = 40：面板里按七个应用排列（笔记 10 / 文本 20 / 文件 30 / 应用 40）。
        ; ⚠ 「输入增强」组内的条目也按模块 order 排，所以 Alt+C / Alt+X 会排在
        ;   CapsLock（60）之前 —— 这是统一命名的副作用，不是漏改排序。
        return {name: this.Name, desc: "PowerShell / DeepSeek / 应用槽位 · Alt+C", order: 40
            , hotkeys: this.GetHotkeys()}
    }
}
