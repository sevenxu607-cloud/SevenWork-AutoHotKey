#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════════
;  ModuleRegistry —— 模块登记 + 统一启动遍历
; ═══════════════════════════════════════════════════════════════════════════
; 模块是类对象，约定带 static Id / Name / Init() / GetHotkeys() / GetContexts()。
; 可选 static Start()：Init 之后、热键就位之后的「对外可见」动作（加载内容 / 恢复配置）。
;
; ⚠ 加一个模块只改两处，且都在 WorkBench.Init() 里（相邻两行）：
;      #Include modules\<名字>\<名字>Module.ahk
;      ModuleRegistry.Register(<名字>Module)
; 组合根只调 InitAll() / StartAll() 两个遍历 —— 不要再往组合根里手写模块 Init()。

class ModuleRegistry {
    static modules := Map()
    ; 启动失败的模块：id → 失败消息。HotkeyRouter 据此跳过它们的热键注册。
    static _failed := Map()
    static _inited := false

    static Register(module) {
        this.modules[module.Id] := module
    }

    static Get(id) => this.modules.Has(id) ? this.modules[id] : ""

    static All() => this.modules

    static IsFailed(id) => this._failed.Has(id)

    ; ─── 统一启动（第一段）：遍历已登记模块，逐个 try ───
    ; 一个模块抛错不带走后面：记日志 + 记入 _failed，其余照常启动。必须在
    ; HotkeyRouter.RegisterAll() 之前调用 —— Init 只做「内部就绪」，不碰窗口。
    static InitAll() {
        if this._inited
            return
        this._inited := true

        for id, mod in this.modules {
            try mod.Init()
            catch as e {
                this._failed[id] := e.Message
                LogError("模块初始化失败：" . id . "（" . this._NameOf(mod) . "）—— "
                    . e.Message . " [" . e.File . " 行 " . e.Line . "]")
            }
        }
    }

    ; ─── 统一启动（第二段）：热键就位之后的「对外可见」动作 ───
    ; 只有实现了 Start() 的模块参与；Init 失败的模块跳过（半初始化不该继续往下走）。
    ; 必须在 HotkeyRouter.RegisterAll() 之后调用 —— 否则窗口先露面、热键还没就绪。
    static StartAll() {
        for id, mod in this.modules {
            if (this.IsFailed(id) || !mod.HasMethod("Start"))
                continue
            try mod.Start()
            catch as e {
                this._failed[id] := e.Message
                LogError("模块启动失败：" . id . "（" . this._NameOf(mod) . "）—— "
                    . e.Message . " [" . e.File . " 行 " . e.Line . "]")
            }
        }
    }

    static _NameOf(mod) => mod.HasProp("Name") ? mod.Name : "?"
}