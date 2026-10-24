#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════════
;  KeysInputModule —— 键位模块生命周期
;  Phase 4：持有 CapsLockFeature 的开关状态与 Alt+Shift+C 热键定义。
;  层内动态热键由 Feature 在开关时经 HotkeyRouter 加 / 卸，不走静态表。
; ═══════════════════════════════════════════════════════════════════════════

class KeysInputModule {
    static Id := "KeysInput"
    static Name := "按键"

    static Init() {
        ; CapsLockFeature 的状态字段在类加载时已就绪；这里保留模块生命周期入口，
        ; 具体配置在 Start() 恢复 —— 必须晚于 HotkeyRouter.RegisterAll()。
    }

    static Start() {
        CapsLockFeature.LoadFromConfig()
    }

    ; 由 HotkeyRouter / WebPanelUI 聚合 —— 注册与 Alt+S 帮助共用这一份数据。
    static GetHotkeys() {
        return [
            {ctx: "global", key: "!+c", group: "输入增强"
                , line: "   Alt+Shift+C      切换 CapsLock 键盘映射"
                , note: "                      （开启后 CapsLock+H/J/K/L = 方向键）"
                , fn: (*) => CapsLockFeature.Toggle()}
        ]
    }

    static GetMetadata() {
        ; order = 60：七个应用顺序里排在「视界」之后、「主题」之前。
        return {name: this.Name, desc: "CapsLock 层 · Alt+Shift+C", order: 60
            , hotkeys: this.GetHotkeys()}
    }
}
