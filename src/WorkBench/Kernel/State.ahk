#Requires AutoHotkey v2.0
; WorkBench/Kernel/State.ahk —— 骨架层的进程内状态
;
; 只剩三样：主窗口、当前日期、隐藏前的位置。
; ⚠ 编辑区 / 状态栏 / 搜索条那些**控件句柄**与**光标位置**已随 RichEdit 退场删除（v2.17）：
;   它们现在归页面（WebView2）自己管，AHK 侧没有可记的东西。要再加状态，先问「谁读它」。

class State {
    static _guiObj := ""
    static _loadedDate := ""

    static _hiddenX := ""
    static _hiddenY := ""
    static _hiddenW := ""
    static _hiddenH := ""

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

    static GetHiddenRect() => {
        x: this._hiddenX, y: this._hiddenY,
        w: this._hiddenW, h: this._hiddenH
    }
    static SetHiddenRect(x, y, w, h) {
        this._hiddenX := x
        this._hiddenY := y
        this._hiddenW := w
        this._hiddenH := h
    }
    static HasHiddenRect() => (this._hiddenX != "")
    static ClearHiddenRect() {
        this._hiddenX := ""
        this._hiddenY := ""
        this._hiddenW := ""
        this._hiddenH := ""
    }
}
