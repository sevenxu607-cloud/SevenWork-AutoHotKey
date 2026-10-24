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

        ; Feature 只保留查找 / 摆位 / 显示能力；热键不再由 Feature 自己注册。
        ; 笔记窗口的让位由 SevenNote 的 WindowFeature 订阅 Launcher.Preparing /
        ; Launcher.Opened / Launcher.Failed 处理；本模块只订阅 Launcher.Move，
        ; 负责把平台算好的伙伴窗口落点应用到自己的终端 / 浏览器窗口上。
        PowerShellFeature.Init()
        DeepSeekFeature.Init()
        EventBus.On("Launcher.Move", (data) => this._OnMove(data))
    }

    ; Launcher.Move：PeerCoordinator 算好「伙伴窗口下移」后广播的**物理外框**。
    ; 终端与 DeepSeek 的 hwnd 都从这里经过，所以放在模块级，不绑定某个 Feature。
    ; 实际搬运交给平台能力 PlacementExecutor —— 它统一处理隐藏 / 最小化守卫；
    ; 「窗口已被用户收起」是正常路径，不算失败；其余失败写日志。
    static _OnMove(data) {
        if !IsObject(data)
            return
        if !(data.HasProp("hwnd") && data.HasProp("x") && data.HasProp("y")
            && data.HasProp("w") && data.HasProp("h"))
            return
        if !(IsNumber(data.x) && IsNumber(data.y)
            && IsNumber(data.w) && IsNumber(data.h))
            return
        if (data.w <= 0 || data.h <= 0)
            return
        if !data.hwnd
            return

        res := PlacementExecutor.Move(data.hwnd
            , {x: data.x, y: data.y, w: data.w, h: data.h}, false)
        if (!res.ok && res.reason != "not-placeable" && res.reason != "minimized")
            LogError("伙伴窗口移动失败：" . res.reason)
    }

    ; 由 HotkeyRouter / WebPanelUI 聚合 —— 注册与 Alt+S 帮助共用这一份数据。
    static GetHotkeys() {
        return [
            {ctx: "global", key: "!c", group: "输入增强"
                , line: "   Alt+C            唤出 / 隐藏 PowerShell（笔记自动让位）"
                , fn: (*) => PowerShellFeature.Toggle()},
            {ctx: "global", key: "!x", group: "输入增强"
                , line: "   Alt+X            呼出 / 隐藏 DeepSeek 网页（笔记自动让位）"
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
