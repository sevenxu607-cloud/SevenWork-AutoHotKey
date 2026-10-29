#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════════
;  HostBridge —— 提示词库（WebView2）的宿主对象（模块：Text）
; ═══════════════════════════════════════════════════════════════════════════
; 与 WorkBench\PanelHostBridge.ahk、modules\SevenNote\HostBridge.ahk 同一套路：
;   · 暴露给 hostObjects 的必须是**顶层函数**（类静态方法走 IDispatch 时报
;     「对象不支持此属性或方法」）；
;   · 返回值一律字符串，前端自己 JSON.parse / 看前缀；
;   · JSON 手拼（v2.0 没有内置 JSON）—— 字符串一律过 JsText.Escape，它是唯一
;     能把 AHK 字符串变成合法 JSON 字面量的地方（返回值含外层引号）。
;
; ⚠ 这份落在**模块里**而不是 WorkBench：分类 / 标题 / 正文都是 Text 模块的业务词，
;   平台不认识它们（.clinerules/02 依赖方向）。唯一借平台的是主题 JSON ——
;   `getTheme` 直接复用 PanelHostBridge 的 ThemeJson()，色板只在平台算一次。
;
; ⚠ 方法键名别用 apply / call / bind / toString / constructor / name / length /
;   prototype：hostObjects 在 JS 侧是 Proxy，`b['apply']` 会先命中内置的
;   Function.prototype，拿到原生函数一调就抛 TypeError（见 PanelHostBridge 注释）。
; ═══════════════════════════════════════════════════════════════════════════

PromptHostPing() => "pong"

PromptHostLib() => PromptStoreService.Lib

; 整份数据一次取完：全部条目 + 分类目录 + 首屏要定位的那一条。
;
; force = "1" 时忽略 PromptStoreService 的缓存重扫 —— 页面每次打开 / F5 都传 1，
; 因为文件可能在 VS Code、资源管理器里被改过（这是「目录即分类」的代价，也是它的好处）。
;
; ⚠ **不传正文**：几百条 × 每条几百字过一遍 COM 序列化要几百毫秒，而列表只用
;   标题 / 分类 / 摘要。复制与编辑都是回 AHK 这边做的（copy / edit），正文用不上。
PromptHostData(force := "") {
    items := PromptStoreService.LoadAll(force = "1")
    cats := PromptStoreService.ListCategories()
    return PromptData.Json(items, cats)
}

; 双击：把正文复制到剪贴板，并在鼠标旁闪一下确认。
; 返回 "ok" / "err:原因"。
;
; ⚠ **不在这里收窗** —— 收窗由前端在拿到 "ok" 之后自己调 close。这里直接 Hide()
;   会在「正在处理 hostObjects 回调」的栈里再注销 Esc 热键，多一层嵌套没必要，
;   而失败的提示也要留在窗口里给用户看见（收了就看不到了）。
PromptHostCopy(path) {
    return PromptWindowFeature.CopyPath(path)
}

; Enter（编辑选中）/ 新建：进**原生**编辑窗 —— 编辑窗本轮没搬，下一轮再说。
; path 为空 = 新建。
PromptHostEdit(path) {
    return PromptWindowFeature.EditPath(path)
}

; 前端请求关窗（Esc 之外的第二条路：按钮 / 收窗动作）
PromptHostSwitchLib(lib) {
    return PromptWindowFeature.SetLib(lib) ? "ok" : "err:unknown-lib"
}

PromptHostClose() {
    PromptWindowFeature.Hide()
    return "ok"
}

; 只记失败，不记普通操作：提示词库天天开，流水账会把日志冲掉
PromptHostLog(msg) {
    LogError("[提示词库] " . ("" . msg))
    return "ok"
}

; 交给 WebHostService.Bind 的方法表。
; ⚠ 键名必须与 web\src\prompt.ts 里的字符串逐个对齐 —— 拼错不报错，
;   前端只会抛「AHK 未提供方法：xxx」，而调用点大多在 try 里，会被静默吞掉。
PromptHostHandlers() {
    return {
        ping:     PromptHostPing,
        getTheme: PanelHostTheme,
        data:     PromptHostData,
        copy:     PromptHostCopy,
        edit:     PromptHostEdit,
        switchLib: PromptHostSwitchLib,
        close:    PromptHostClose,
        log:      PromptHostLog
    }
}


; ═══════════════════════════════════════════════════════════════════════════
;  PromptData —— 列表页要显示的全部数据（序列化）
; ═══════════════════════════════════════════════════════════════════════════
; 前端契约见 web\src\prompt.ts 的 PromptData 接口，字段名两边逐个对齐。
class PromptData {
    static Json(items, categories) {
        cats := ""
        for c in categories
            cats .= (cats ? "," : "") . JsText.Escape(c)

        rows := ""
        for it in items {
            rows .= (rows ? "," : "")
                . '{"title":'    . JsText.Escape(it.title)
                . ',"category":' . JsText.Escape(it.category)
                . ',"path":'     . JsText.Escape(it.path)
                . ',"summary":'  . JsText.Escape(it.summary)
                . ',"mtime":'    . JsText.Escape(it.mtime)
                . "}"
        }

        ; focus：编辑窗保存 / 删除之后要回到的那一条（绝对路径，空串 = 不定位）。
        ; 由 PromptWindowFeature.FocusPath() 记下，页面重拉数据时据此选中。
        return '{"root":'       . JsText.Escape(PromptStoreService.Root())
            . ',"categories":[' . cats . "]"
            . ',"items":['      . rows . "]"
            . ',"focus":'       . JsText.Escape(PromptWindowFeature.FocusId())
            . "}"
    }
}
