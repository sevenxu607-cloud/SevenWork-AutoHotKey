#Requires AutoHotkey v2.0
; WorkBench/Kernel/State.ahk —— 骨架层的进程内状态
;
; 只剩两样：主窗口、当前日期。
; ⚠ 隐藏前的位置记忆已随「伙伴窗口适配」一起删除（v2.18）：笔记固定落记录区，
;   不再需要记住用户拖到哪。编辑区 / 状态栏 / 搜索条那些控件句柄与光标位置也早已
;   随 RichEdit 退场。要再加状态，先问「谁读它」。

class State {
    static _guiObj := ""
    static _loadedDate := ""

    static GetGui() => this._guiObj
    ; 供 #HotIf 等表达式安全取主窗口句柄：GUI 尚未创建时返回 0
    ; （否则 "".Hwnd 会抛 "String has no property named Hwnd"）
    static GetGuiHwnd() => IsObject(this._guiObj) ? this._guiObj.Hwnd : 0
    static SetGui(g) {
        this._guiObj := g
        ; ⚠ 当前没有订阅者：这是「窗口就绪」扩展点，不是漏掉的接线（骨架层冻结，只加不改）
        EventBus.Emit("Gui.Ready", g)
    }

    static GetDate() => this._loadedDate
    static SetDate(d) {
        old := this._loadedDate
        this._loadedDate := d
        EventBus.Emit("Date.Changed", {old: old, new: d})
    }
}
