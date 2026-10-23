#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════════
;  PanelHostBridge —— 工作台面板（WebView2）的宿主对象
; ═══════════════════════════════════════════════════════════════════════════
;  与 modules\SevenNote\HostBridge.ahk 同一套路：
;    · 暴露给 hostObjects 的必须是**顶层函数**（类静态方法走 IDispatch 时报
;      「对象不支持此属性或方法」）；
;    · 返回值一律字符串，前端自己解析。
;  数据聚合放 PanelData 类里：好读，也能被探针单独调用。
;
;  **整份数据一次取完**：切页是纯前端行为，来回过 hostObjects 每趟都是一次
;  跨进程 COM 调用。全部热键才 40 出头，一次给完最省事、也避免「切页时闪一下
;  旧内容」。代价是热键表 / 设置值变了要重拉一次（前端在保存后自己调 getPanel）。
;
;  ⚠ JSON 是**手拼**的（v2.0 没有内置 JSON）：字符串一律过 JsText.Escape，
;    它是唯一能把 AHK 字符串变成合法 JSON 字面量的地方（返回值含外层引号）。
; ═══════════════════════════════════════════════════════════════════════════

PanelHostPing() => "pong"
PanelHostVersion() => Config.Version

; ─── 语义色板 → JSON ────────────────────────────────────────────────────────
; 前端 JSON.parse 后 applyTheme 一次设全 --sw-*。
; ⚠ 这一份**上收到平台侧**：笔记窗与面板都要同一个主题，而「平台去调模块里的
;   函数」是反向依赖（.clinerules/02）。所以序列化住在这里，模块侧只转发。
; ⚠ 字段名与 web\src\ahk.ts 的 Theme 接口逐个对齐，改一边必须改另一边。
; ⚠ 有中文（主题名），引号 / 反斜杠必须过 JsText.Escape —— 手拼 JSON 只在这两处。
ThemeJson() {
    p := ThemeService.Palette()
    return "{"
        . '"name":'     . JsText.Escape(p.name)   . ","
        . '"win":'      . JsText.Escape(p.win)    . ","
        . '"edBg":'     . JsText.Escape(p.edBg)   . ","
        . '"text":'     . JsText.Escape(p.text)   . ","
        . '"dim":'      . JsText.Escape(p.dim)    . ","
        . '"accent":'   . JsText.Escape(p.accent) . ","
        . '"border":'   . JsText.Escape(p.border) . ","
        . '"codeBg":'   . JsText.Escape(p.codeBg) . ","
        . '"dark":'     . (p.dark ? "true" : "false") . ","
        . '"bg":'       . JsText.Escape(p.bg)     . ","
        . '"bgAlpha":'  . p.bgAlpha . ","
        . '"style":'    . JsText.Escape(p.style)  . ","
        . '"material":' . ThemeMaterialJson(p.material)
        ; 全局外观覆盖（「外观」模块写的四项）—— 前端把它们写成
        ; --sw-radius-lg / --sw-dur-* / 密度变量。**必须在这里透传**：
        ; 少一个字段，面板里调完保存后界面纹丝不动，而日志里什么都没有。
        . ',"radius":'  . p.radius
        . ',"motion":'  . JsText.Escape(p.motion)
        . ',"density":' . JsText.Escape(p.density)
        . ',"durFast":' . JsText.Escape(p.durFast)
        . ',"dur":'     . JsText.Escape(p.dur)
        . ',"durSlow":' . JsText.Escape(p.durSlow)
        . "}"
}

; material 是 AHK 对象（键 → CSS 值），转成一层扁平 JSON。
; 不引通用序列化器：值全是 CSS 字面量（"14px" / "rgba(...)"），过一遍 JsText.Escape
; 就够；键名也过滤成 [a-z0-9-]，防止主题表里笔误把奇怪名字写进 --sw-*。
; 空 / 非对象一律给 {}，前端 JSON.parse 后拿到空对象，行为与不推这个字段一致。
ThemeMaterialJson(m) {
    if !IsObject(m)
        return "{}"
    out := ""
    for k, v in m {
        if !RegExMatch(k, "^[a-z][a-z0-9-]*$")
            continue
        out .= (out ? "," : "") . JsText.Escape(k) . ":" . JsText.Escape("" . v)
    }
    return "{" . out . "}"
}

PanelHostTheme() {
    return ThemeJson()
}

; 整份面板数据：应用信息 + 每页（视图 / 模块）的描述 + 热键 + 设置字段
PanelHostData() {
    return PanelData.Json()
}

; 保存某模块的设置。
;
; ⚠ 参数**固定 8 个**，不是可变的 —— hostObjects 走 IDispatch，变参（`args*`）
;   在这种调用方式下不可靠，而前端也拿不到「AHK 想要几个」的信息。固定槽位
;   + 前端永远补满 8 个，是最省事又不会踩坑的写法；超过 8 个字段要加长这里
;   （目前最多的是折叠模块的 3 个）。
; ⚠ 顺序 = GetSettingsSpec().fields 的声明顺序，PanelData.Apply 只取前 n 个。
; 返回 "ok" | "err:原因"（前端只看前缀，原因直接显示给用户）。
PanelHostApply(moduleId, v1 := "", v2 := "", v3 := "", v4 := ""
    , v5 := "", v6 := "", v7 := "", v8 := "") {
    return PanelData.Apply(moduleId, [v1, v2, v3, v4, v5, v6, v7, v8])
}

; 前端请求关窗（Esc 之外的第二条路：底栏的「关闭」按钮）
PanelHostClose() {
    WebPanelUI.Close()
    return "ok"
}

; 选文件夹（系统对话框）。前端「浏览…」按钮走这里 —— 让用户手打路径不可接受。
; 返回选中的绝对路径（已规整）；取消 / 出错返回空串，前端保持输入框原值。
;
; ⚠ DirSelect 是**模态**的，会阻塞 AHK 主线程直到用户选完 —— 与改造前的原生面板
;   一致，期间热键不响应。
; ⚠ 第 2 参数 0x41 = BIF_RETURNONLYFSDIRS(0x1) | BIF_NEWDIALOGSTYLE(0x40)。
;   传 0 拿到的是老式对话框：没有地址栏、不能粘贴路径、不能拖文件夹进来。
; ⚠ 本机 v2.0.27 的 DirSelect 只收 **3 个参数**（StartingFolder / Options / Prompt），
;   没有「父窗口」这一位 —— 传第 4 个直接抛 Too many parameters。对话框压在面板
;   下面这件事只能靠「面板不置顶」解决（见 WebPanelUI._Build）。
PanelHostBrowse(current := "") {
    start := PanelData.BrowseStart(current)
    try sel := DirSelect(start, 0x41, "选择这个槽位要打开的文件夹（地址栏可直接粘贴路径）")
    catch as e {
        LogError("面板打开文件夹选择框失败：" . e.Message)
        return ""
    }
    if (sel = "")
        return ""
    sel := PanelData.NormalizePath(sel)
    PanelData._lastBrowse := sel
    return sel
}

; 前端把关键失败写进 AHK 日志。
; 为什么需要：JS 侧的错误只活在页面里 —— 用户在真机上只会看到状态栏一行看不懂
; 的中文，而 .clinerules/03 教的排错第一步是「先看 _error.log」，那里却什么都没有。
; 只记失败，不记普通操作：面板天天开，流水账会把日志冲掉。
PanelHostLog(msg) {
    LogError("[面板] " . ("" . msg))
    return "ok"
}

; 交给 WebHostService.Bind 的方法表。
; ⚠ 名字必须与 web\src\panel.ts 里的字符串逐个对齐 —— 拼错不报错，
;   前端只会抛「AHK 未提供方法：xxx」，而调用点大多在 try 里，会被静默吞掉。
PanelHostHandlers() {
    return {
        ping:     PanelHostPing,
        version:  PanelHostVersion,
        getTheme: PanelHostTheme,
        getPanel: PanelHostData,
        browse:   PanelHostBrowse,
        ; ⚠ 键名**不能叫 apply**：hostObjects 在 JS 侧是 Proxy，`b['apply']` 会先命中
        ;   内置的 Function.prototype.apply，于是前端拿到的是一个原生函数、调用时抛
        ;   「TypeError: Function.prototype.apply was called on ...」。同类禁用名还有
        ;   call / bind / toString / constructor / name / length / prototype。
        saveSettings: PanelHostApply,
        close:    PanelHostClose,
        ; ⚠ 只记失败（见 PanelHostLog 上方）—— 名字别用 apply / call / bind 这类
        log:      PanelHostLog
    }
}


; ═══════════════════════════════════════════════════════════════════════════
;  PanelData —— 面板要显示的全部数据（聚合 + 序列化 + 保存）
; ═══════════════════════════════════════════════════════════════════════════
;  平台只负责「怎么摆」：模块名 / 描述 / 热键 / 设置字段全部由各模块自己声明
;  （GetMetadata / GetSettingsSpec），这里不认识任何业务名词。
class PanelData {
    ; 第一行固定是「全部热键」视图 —— 它不是模块，靠前端加 ≡ 前缀区分
    static OverviewId := "__all"

    ; 组的显示顺序（沿用改造前的首选项）。
    ; 模块新加的组不在表里时按首次出现顺序追加 —— 加模块不用改这里。
    static _GroupOrder := ["平台", "窗口", "外观", "输入增强", "搜索", "文本", "文件夹"
        , "保存", "日期与标签", "编辑", "分段"]

    ; ─── 整份 JSON ─────────────────────────────────────────────────────
    static Json() {
        entries := this._Collect()
        items := this._ModuleItems()

        out := "{"
            . '"app":'     . JsText.Escape(Config.AppName) . ","
            . '"version":' . JsText.Escape(Config.Version) . ","
            . '"vault":'   . JsText.Escape(Config.GetVault()) . ","
            . '"total":'   . entries.Length . ","
            . '"modules":' . items.Length . ","
            ; 打开时停在哪一页：AHK 侧 ShowHelp(id) 会把目标记进 FocusId，
            ; 页面 onMounted 读它 —— 比「导航完再 Eval(goto)」稳（那次可能落在
            ; 页面脚本就绪之前，静默丢掉）。
            . '"focus":'   . JsText.Escape(WebPanelUI.FocusId()) . ","
            . '"rows":['

        ; ── 第 1 行：「全部热键」按旧分组排列（就是老 Alt+S 的样子）
        out .= '{"id":' . JsText.Escape(this.OverviewId)
            . ',"kind":"view"'
            . ',"name":' . JsText.Escape("全部热键")
            . ',"desc":' . JsText.Escape("所有模块的热键汇总 · 按分组排列")
            . ',"count":' . entries.Length
            . ',"failed":false'
            . ',"groups":' . this._GroupedJson(entries)
            . ',"spec":null}'

        for it in items
            out .= "," . this._RowJson(it)

        return out . "]}"
    }

    ; ─── 一个模块页 ────────────────────────────────────────────────────
    ; 模块页的热键**不分组**：一个模块通常只占 1~2 个组，再分组只会把两行字
    ; 拆成三块。平铺给前端，它自己按 items 渲染一段列表。
    static _RowJson(it) {
        return '{"id":' . JsText.Escape(it.id)
            . ',"kind":"module"'
            . ',"name":' . JsText.Escape(it.name)
            . ',"desc":' . JsText.Escape(it.desc)
            . ',"count":' . it.count
            . ',"failed":' . (it.failed ? "true" : "false")
            . ',"hotkeys":' . this._FlatJson(it.hotkeys)
            . ',"spec":' . this._SpecJson(it.spec)
            . "}"
    }

    ; 按组排列的热键（只给「全部热键」视图用）
    static _GroupedJson(entries) {
        out := ""
        for g in this._OrderedGroups(entries) {
            items := ""
            for e in entries {
                if (e.group != g)
                    continue
                items .= (items ? "," : "") . this._ItemJson(e.hk)
            }
            out .= (out ? "," : "") . '{"name":' . JsText.Escape(g)
                . ',"items":[' . items . "]}"
        }
        return "[" . out . "]"
    }

    ; 平铺的热键（模块页用）
    static _FlatJson(hotkeys) {
        out := ""
        for hk in hotkeys
            out .= (out ? "," : "") . this._ItemJson(hk)
        return "[" . out . "]"
    }

    ; 一条热键 → {key, label, note?}
    ;
    ; hk.line 的既有格式是 "   Alt+Z            呼出 / 隐藏"（3 空格 + 键名 +
    ; 空格填充 + 说明）。前端用比例字体，靠空格对齐必然歪，所以在这里就拆成
    ; 两列 —— 页面渲染的是真正的两栏，不是一串空格。
    ; ⚠ 不能用 hk.key：那是 AHK 的热键语法（"$^s" / "!Up"），给人看的在 line 里。
    static _ItemJson(hk) {
        line := hk.HasProp("line") ? hk.line : ("   " . (hk.HasProp("key") ? hk.key : ""))
        key := ""
        label := ""
        if RegExMatch(line, "^\s*(\S+)\s+(.*)$", &m) {
            key := m[1]
            label := m[2]
        } else {
            key := Trim(line)
        }
        out := '{"key":' . JsText.Escape(key) . ',"label":' . JsText.Escape(label)
        if hk.HasProp("note")
            out .= ',"note":' . JsText.Escape(hk.note)
        return out . "}"
    }

    ; 设置声明 → 可序列化的形状。
    ; ⚠ apply 是 Func 对象，**不能**进 JSON —— 前端只被告知「这一页能存」
    ;   （hasApply），存的时候带着 moduleId 回来找。platform 也不认识字段的业务含义。
    static _SpecJson(spec) {
        if !IsObject(spec)
            return "null"

        fields := spec.HasProp("fields") ? spec.fields : []
        body := ""
        i := 0
        for f in fields {
            i += 1
            body .= (i > 1 ? "," : "")
                . '{"key":'     . JsText.Escape(f.HasProp("key") ? f.key : ("f" . i))
                . ',"label":'   . JsText.Escape(f.HasProp("label") ? f.label : "")
                . ',"kind":'    . JsText.Escape(f.HasProp("kind") ? f.kind : "text")
                . ',"value":'   . JsText.Escape(f.HasProp("value") ? f.value : "")
                . ',"placeholder":' . JsText.Escape(f.HasProp("placeholder") ? f.placeholder : "")
                ; 以下四项给 select / range 用，text / folder 一律给空值 ——
                ; 前端按 kind 选控件，不认识这些字段也不会出错（只是没用上）。
                . ',"options":' . this._OptionsJson(f.HasProp("options") ? f.options : "")
                . ',"min":'     . JsText.Escape(f.HasProp("min") ? ("" . f.min) : "")
                . ',"max":'     . JsText.Escape(f.HasProp("max") ? ("" . f.max) : "")
                . ',"step":'    . JsText.Escape(f.HasProp("step") ? ("" . f.step) : "")
                . ',"unit":'    . JsText.Escape(f.HasProp("unit") ? f.unit : "")
                . "}"
        }

        return '{"title":' . JsText.Escape(spec.HasProp("title") ? spec.title : "设置")
            . ',"hint":' . JsText.Escape(spec.HasProp("hint") ? spec.hint : "")
            . ',"hasApply":' . (spec.HasProp("apply") ? "true" : "false")
            . ',"fields":[' . body . "]}"
    }

    ; select 字段的候选值 → JSON 字符串数组。
    ; 用「值即显示」：不另存 key，前端少一层映射，模块也不必维护一份 id→label 表。
    ; 没有 options（text / folder / range）一律给 []。
    static _OptionsJson(opts) {
        if !IsObject(opts)
            return "[]"
        out := ""
        i := 0
        for o in opts {
            i += 1
            out .= (i > 1 ? "," : "") . JsText.Escape("" . o)
        }
        return "[" . out . "]"
    }

    ; ─── 模块行 ────────────────────────────────────────────────────────
    ; 顺序 = GetMetadata().order 升序，同 order 按 Id 字典序 ——
    ; 别让它取决于 Map 的遍历顺序，那会在加模块时悄悄变。
    static _ModuleItems() {
        items := []
        for id, module in ModuleRegistry.All() {
            meta := this._MetadataOf(module)
            failed := ModuleRegistry.IsFailed(id)
            name := meta.HasProp("name") ? meta.name : id
            desc := meta.HasProp("desc") ? meta.desc : ""
            ; 启动失败的模块**仍然占一行**并标 (失败)：让它从列表里消失，
            ; 等于让用户以为「模块没了」。热键一条都没注册，页面要写明。
            if failed {
                name .= "(失败)"
                desc := "启动失败 · 热键未注册"
            }
            hotkeys := meta.HasProp("hotkeys") ? meta.hotkeys : []
            items.Push({
                id:      id,
                name:    name,
                desc:    desc,
                order:   meta.HasProp("order") ? meta.order : 100,
                count:   hotkeys.Length,
                failed:  failed,
                hotkeys: failed ? [] : hotkeys,
                spec:    failed ? "" : this._SpecOf(module)
            })
        }
        this._SortItems(items)
        return items
    }

    ; AHK v2.0 的 Array 没有 Sort；条目最多十几个，插入排序足够且稳定
    static _SortItems(items) {
        i := 1
        while (i <= items.Length) {
            j := i
            while (j > 1 && this._ItemBefore(items[j], items[j - 1])) {
                tmp := items[j]
                items[j] := items[j - 1]
                items[j - 1] := tmp
                j -= 1
            }
            i += 1
        }
    }

    static _ItemBefore(a, b) {
        if (a.order != b.order)
            return a.order < b.order
        return StrCompare(a.id, b.id) < 0
    }

    ; ─── 元数据 / 设置：模块可选实现，缺了就退回最低限度 ────────────────
    static _MetadataOf(module) {
        if module.HasMethod("GetMetadata")
            return module.GetMetadata()
        ; 兼容还没实现 GetMetadata 的模块：只提供 GetHotkeys 也能出现在列表里
        hotkeys := module.HasMethod("GetHotkeys") ? module.GetHotkeys() : []
        return {name: module.Id, desc: "", order: 100, hotkeys: hotkeys}
    }

    static _SpecOf(module) {
        if !module.HasMethod("GetSettingsSpec")
            return ""
        try spec := module.GetSettingsSpec()
        catch as e {
            ; 一个模块的设置声明写坏不该让整个面板打不开 —— 当作「没有设置」
            LogError("读取模块设置失败：" . module.Id . " —— " . e.Message)
            return ""
        }
        return IsObject(spec) ? spec : ""
    }

    ; ─── 全部热键：平台 + 各模块，按 order / 声明顺序稳定排序 ────────────
    ; ⚠ 启动失败的模块**不进**这张表：它的热键一条都没注册，列出来等于骗人。
    ;   模块页里会明确写「热键未注册」。
    static _Collect() {
        entries := []
        seq := 0

        for hk in WorkBench.GetHotkeys() {
            entries.Push({order: 0, seq: seq, group: this._GroupOf(hk), hk: hk})
            seq += 1
        }

        for id, module in ModuleRegistry.All() {
            if ModuleRegistry.IsFailed(id)
                continue
            meta := this._MetadataOf(module)
            order := meta.HasProp("order") ? meta.order : 100
            if !meta.HasProp("hotkeys")
                continue
            for hk in meta.hotkeys {
                entries.Push({order: order, seq: seq, group: this._GroupOf(hk), hk: hk})
                seq += 1
            }
        }

        this._SortEntries(entries)

        ; 同一 ctx + key 只留第一次出现的那条（平台优先）
        result := []
        seen := Map()
        for entry in entries {
            ctxName := entry.hk.HasProp("ctx") ? entry.hk.ctx : ""
            keyName := entry.hk.HasProp("key") ? entry.hk.key : ""
            uniq := ctxName . "|" . keyName
            if seen.Has(uniq)
                continue
            seen[uniq] := true
            result.Push(entry)
        }
        return result
    }

    static _SortEntries(entries) {
        i := 1
        while (i <= entries.Length) {
            j := i
            while (j > 1 && this._EntryBefore(entries[j], entries[j - 1])) {
                tmp := entries[j]
                entries[j] := entries[j - 1]
                entries[j - 1] := tmp
                j -= 1
            }
            i += 1
        }
    }

    static _EntryBefore(a, b) {
        if (a.order != b.order)
            return a.order < b.order
        return a.seq < b.seq
    }

    static _GroupOf(hk) => hk.HasProp("group") ? hk.group : "其他"

    ; 组的显示顺序：先按首选项，不在表里的按首次出现顺序追加到末尾
    static _OrderedGroups(entries) {
        groups := []
        seen := Map()
        for groupName in this._GroupOrder {
            if this._HasGroup(entries, groupName) {
                groups.Push(groupName)
                seen[groupName] := true
            }
        }
        for entry in entries {
            if !seen.Has(entry.group) {
                groups.Push(entry.group)
                seen[entry.group] := true
            }
        }
        return groups
    }

    static _HasGroup(entries, groupName) {
        for entry in entries {
            if (entry.group = groupName)
                return true
        }
        return false
    }

    ; ─── 文件夹选择（纯判断，不碰窗口）────────────────────────────────
    ; 上次浏览到的目录：连配三个槽位时不用每次重新点下去
    static _lastBrowse := ""

    ; 优先级：输入框里已填的 → 上次浏览到的 → D 盘（本机资料盘）→ 我的文档。
    ; ⚠ 只决定「从哪开始看」，不限制能去哪 —— 新式对话框可以在地址栏输任意路径。
    static BrowseStart(cur) {
        for p in [cur, this._lastBrowse] {
            if (p != "" && DirExist(p))
                return p
        }
        if DirExist("D:\")
            return "D:\"
        return A_MyDocuments
    }

    ; 去两端空白与末尾反斜杠；盘根（D:\）保留反斜杠。
    ; 与 FolderSlotService.Normalize / ExplorerProbe.NormalizePath 同一套规则 ——
    ; 三处规则不一致的话，「一眼看着相同的路径」会被判成不同目录。
    static NormalizePath(path) {
        p := RTrim(Trim(path), "\")
        if RegExMatch(p, "^[A-Za-z]:$")
            p .= "\"
        return p
    }

    ; ─── 保存 ──────────────────────────────────────────────────────────
    ; 找模块 → 取 spec.apply → 把前 n 个值（n = fields 数）交给它。
    ;
    ; ⚠ **先落到局部变量再调**：`spec.apply(vals)` 走的是方法查找，属性里存的
    ;   Func 根本不会被调用（抛 Too many parameters），而且会被下面的 catch
    ;   吞成一条读不懂的日志。见 .clinerules/03 的踩坑表。
    ; ⚠ 值由前端按 fields 声明顺序送来；平台不 Trim、不校验 —— 那是模块自己的
    ;   事（apply 里可以把值规整成最终形态，见 .clinerules/02）。
    static Apply(moduleId, values) {
        module := ModuleRegistry.Get(moduleId)
        if !module
            return "err:模块不存在：" . moduleId

        spec := this._SpecOf(module)
        if (!IsObject(spec) || !spec.HasProp("apply"))
            return "err:该模块没有可保存的设置"

        fn := spec.apply
        if !IsObject(fn)
            return "err:该模块的 apply 不是函数"

        fields := spec.HasProp("fields") ? spec.fields : []
        vals := []
        i := 1
        while (i <= fields.Length) {
            vals.Push(values[i])
            i += 1
        }

        try ok := fn(vals)
        catch as e {
            LogError("保存模块设置失败：" . moduleId . " —— " . e.Message)
            return "err:" . e.Message
        }

        return ok ? "ok" : "err:保存失败（配置目录不可写？详见 _error.log）"
    }
}
