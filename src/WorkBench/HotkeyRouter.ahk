#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════════
;  HotkeyRouter —— 热键注册的唯一入口
; ═══════════════════════════════════════════════════════════════════════════
; Phase 1 包住原 RegisterHotkeys()；Phase 2 起 contexts 由
; SevenNoteModule.GetContexts() 提供，Router 不再直接引用 SearchFeature。
; Phase 4 起提供 Add / Remove：模块的层内热键（CapsLock / HJKL）动态加卸。

class HotkeyRouter {
    static _contexts := {}
    static _dynamic := Map()

    ; Phase 5：静态热键不再由组合根拼表 —— 平台取 WorkBench.GetHotkeys()，
    ; 各模块取 GetHotkeys()，上下文取各模块 GetContexts()，Router 只负责注册。
    static RegisterAll() {
        contexts := {}
        table := []

        for hk in WorkBench.GetHotkeys()
            table.Push(hk)

        for id, module in ModuleRegistry.All() {
            ; 启动失败的模块：热键不注册（按了只会复现同一个错），失败原因已在 InitAll 里记过
            if ModuleRegistry.IsFailed(id)
                continue
            if module.HasMethod("GetContexts") {
                moduleContexts := module.GetContexts()
                for name in moduleContexts.OwnProps()
                    contexts.%name% := moduleContexts.%name%
            }
            if module.HasMethod("GetHotkeys") {
                for hk in module.GetHotkeys()
                    table.Push(hk)
            }
        }

        this._contexts := contexts

        ; 同一 ctx + key 只注册一次（平台先收集，所以平台热键优先）；
        ; 模块误把平台热键再声明一遍时，不会在注册阶段悄悄盖掉平台回调。
        staticTable := []
        seenKeys := Map()
        for hk in table {
            uniq := hk.ctx . "|" . hk.key
            if seenKeys.Has(uniq) {
                LogError("热键重复声明，已忽略：" . uniq)
                continue
            }
            seenKeys[uniq] := true
            staticTable.Push(hk)
        }

        ; 注册顺序 = 全局 → 各模块声明的上下文（按声明顺序）。
        ; 全局变体（无上下文）的优先级天然最低，所以「先建全局」不会抢上下文变体的命中。
        ; ⚠ 上下文名不再写死（Phase 6）：模块 GetContexts() 报什么就注册什么。
        ;   以前这是 ["global", "editor", "search"] 三个字面量 —— 新模块加上下文
        ;   必须回来改 Router，而忘了改的后果是「它的 Esc / Enter 一条都没注册」。
        ctxNames := ["global"]
        for name in contexts.OwnProps()
            ctxNames.Push(name)

        for ctxName in ctxNames {
            this._ApplyContext(ctxName)
            for hk in staticTable {
                if (hk.key = "" || hk.ctx != ctxName)
                    continue
                try
                    Hotkey(hk.key, hk.fn, "On")
                catch as e
                    LogError("热键注册失败：" . hk.key . " —— " . e.Message)
            }
        }
        HotIf()   ; 复位：别把上下文漏给后面动态注册的热键

        ; 声明了上下文、但没有任何模块在 GetContexts() 里提供它 —— 这些热键
        ; **一条都没注册**（上面只遍历 global + 已知 ctx）。不报出来的话，
        ; 表现就是「按了没反应」，而日志干干净净。
        for hk in staticTable {
            if (hk.key = "" || hk.ctx = "" || hk.ctx = "global")
                continue
            if !contexts.HasProp(hk.ctx)
                LogError("热键的上下文不存在，已跳过：" . hk.ctx . " | " . hk.key)
        }
    }

    ; 动态注册（Phase 4：CapsLock 层开关时调用）。
    ; 同 key 重复 Add 先卸再装，避免残留旧回调；失败只记日志，返回 false。
    static Add(key, fn, ctx := "global") {
        if this._dynamic.Has(key)
            this.Remove(key)
        try {
            this._ApplyContext(ctx)
            Hotkey(key, fn, "On")
            this._dynamic[key] := {fn: fn, ctx: ctx}
            return true
        } catch as e {
            LogError("动态热键注册失败：" . key . " —— " . e.Message)
            return false
        } finally {
            HotIf()
        }
    }

    static Remove(key) {
        if !this._dynamic.Has(key)
            return
        try {
            Hotkey(key, "Off")
        } catch as e {
            LogError("动态热键注销失败：" . key . " —— " . e.Message)
        }
        this._dynamic.Delete(key)
        HotIf()
    }

    ; 上下文 → HotIf。三种输入：
    ;   · "global" 或没在 contexts 里出现的名字 → 无上下文（全系统）
    ;   · 传函数对象（兼容旧调用）              → 直接用它
    ;   · contexts 里的名字                     → 取它对应的函数
    ;
    ; ⚠ 为什么是「按表查」而不是 switch：
    ;   原来 switch 只认 global / editor / search，新加的 prompts 会落到 default 分支
    ;   变成 HotIf() —— 也就是把 Esc / Enter 注册成**全系统热键**。Phase 6 加 Text
    ;   模块时正是这里挡着，所以改成表驱动，新 ctx 自动生效。
    static _ApplyContext(ctx) {
        if IsObject(ctx) {
            HotIf(ctx)
            return
        }
        if (ctx = "global" || !IsObject(this._contexts) || !this._contexts.HasProp(ctx)) {
            HotIf()
            return
        }
        HotIf(this._contexts.%ctx%)
    }
}
