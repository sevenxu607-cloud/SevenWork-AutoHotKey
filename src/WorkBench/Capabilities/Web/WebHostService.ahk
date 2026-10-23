#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════
;  WebHostService —— WebView2 宿主（平台能力 / Capability）
; ═══════════════════════════════════════════════════════════════════════
;  纯能力：只收 hwnd / 路径 / 字符串，返回 {ok, ...}；失败给 {ok:false, reason}。
;  不读 Config / State、不发 EventBus、不认识 modules/*（见 .clinerules/02）。
;
;  为什么算能力而不是服务：它只做两件事 ——
;    ① 把一个 Chromium 子窗口挂到给定 hwnd 上；
;    ② 把一个目录映射成 https://<host>/。
;  两件都跟工作台业务无关，任何模块都能用，所以归 Capability。
;
;  ⚠ 库目录结构不能动：WebView2.ahk 靠 A_LineFile\..\64bit\ 找 Loader，还靠末尾的
;    #Include ..\ComVar.ahk / ..\Promise.ahk 找上一层的两个文件。三者必须按
;    src\lib\ 的原样摆放；摆错时报的是 Missing ")" 这类假语法错，很容易误判成版本不兼容。
;
;  ⚠ 别用 Navigate("data:text/html,...#...")：data: URL 里未编码的 # 被当成 fragment
;    分隔符，整段 HTML 被截断成白屏，而 ExecuteScriptAsync 照样能跑 ——
;    表现是「日志全绿、画面全白」。要直接给 HTML 字符串就用 CoreWebView2.NavigateToString()。
;
;  ⚠ 报错一律返回 reason 而不是 LogError：日志归属由调用方（Feature / Module）决定。
; ═══════════════════════════════════════════════════════════════════════
#Include ..\..\..\lib\WebView2\WebView2.ahk

class WebHostService {
    ; v2.10：**多实例**。从前是单例（_ctrl / _core / _hwnd 各一个），
    ; 挂第二个窗口时 Mount 会先 Destroy() —— 面板一开、笔记窗的 WebView2 就没了，
    ; 表现为「关掉面板后笔记窗一片纯底色」。改成 hwnd → {ctrl, core, host} 的槽位表。
    static _slots := Map()
    ; 最近挂载的 hwnd：无参调用（Eval / Resize …）默认作用在它身上。
    ; ⚠ 新代码**一律显式传 hwnd** —— 否则「最后挂的是哪个窗口」决定行为，
    ;   面板一开，笔记模块的无参 Resize 就打到面板上去了。
    static _cur := 0

    ; ─── 挂载 ───────────────────────────────────────────────────────────
    ; hwnd    父窗口（Gui.Hwnd）；同一个 hwnd 重复 Mount 只做 Fill，不重建 Chromium
    ; distDir 前端构建产物目录（绝对路径）
    ; host    虚拟主机名，缺省 app.local
    ; bgColor 0xAARRGGBB 首帧底色（防白闪）
    ; dataDir WebView2 user data 目录；缺省用 SevenWork 自己的，
    ;         **不要**用库默认的 Edge 目录 —— 那里跟 Edge 浏览器共用，缓存/清理会互相影响
    ;         ⚠ 多个窗口**必须给不同 dataDir**：同一 user data folder 建第二个
    ;         CoreWebView2Environment 会失败（Chromium 的 profile 锁），
    ;         而失败发生在 await() 里，看起来只是「第二个窗口白屏」。
    ; 返回 {ok:true, ctrl, core, reused} | {ok:false, reason}
    static Mount(hwnd, distDir, host := "app.local", bgColor := 0xFF0B1624, dataDir := "") {
        if !hwnd || !DllCall("user32\IsWindow", "ptr", hwnd, "int")
            return {ok: false, reason: "父窗口无效: " . hwnd}

        ; ⚠ 必须先规范化：SetVirtualHostNameToFolderMapping 不收含 .. 的路径，
        ;   传进去表现为「导航成功但页面是 Edge 的『无法访问此页面』」——导航本身不报错，很难查。
        distDir := this._NormPath(distDir)
        if !DirExist(distDir)
            return {ok: false, reason: "前端目录不存在: " . distDir}

        ; 同一个父窗口 → 复用，只跟一次尺寸（面板反复开关时省掉 200ms 重建 + 内存抖动）
        if this._slots.Has(hwnd) {
            slot := this._slots[hwnd]
            this._cur := hwnd
            this.Resize(hwnd)
            return {ok: true, ctrl: slot.ctrl, core: slot.core, reused: true}
        }

        ; ⚠ 这里**不再 Destroy 别的窗口** —— 各窗口各留一份，
        ;   谁该关由它的主人（模块 / 平台界面）自己决定。

        try {
            ctrl := WebView2.CreateControllerAsync(hwnd, 0, dataDir || (EnvGet("LOCALAPPDATA") . "\SevenWork\WebView2")).await()
        } catch as e {
            return {ok: false, reason: "创建 WebView2 失败: " . e.Message}
        }

        ; 首帧底色：Chromium 默认是白的，先在原地铺一层深色，页面到位前不闪白
        try ctrl.DefaultBackgroundColor := bgColor
        catch {
            ; Runtime 不支持 IID_2 时忽略 —— 只影响首帧观感，没人需要知道
        }

        try {
            core := ctrl.CoreWebView2
            core.SetVirtualHostNameToFolderMapping(host, distDir, 1)
        } catch as e {
            try ctrl.Close()
            return {ok: false, reason: "映射虚拟主机失败: " . e.Message}
        }

        this._slots[hwnd] := {ctrl: ctrl, core: core, host: host}
        this._cur := hwnd
        return {ok: true, ctrl: ctrl, core: core, reused: false}
    }

    ; ─── 取槽位（内部）────────────────────────────────────────────────
    ; hwnd 省略 = 最近挂载的那个。拿不到返回 ""，调用方一律按「尚未挂载」处理。
    static _Slot(hwnd := 0) {
        h := hwnd || this._cur
        if (!h || !this._slots.Has(h))
            return ""
        return this._slots[h]
    }

    ; ─── 导航到虚拟主机下的路径 ─────────────────────────────────────────
    ; ⚠ 虚拟主机映射**不做目录索引**：Navigate("https://app.local/") 会落到 Edge 的
    ;   「无法访问此页面」，而 SetVirtualHostNameToFolderMapping 的 HRESULT 仍是 S_OK、
    ;   导航也不抛错 —— 只有画面是错误页，是最难查的一类问题。根路径必须补成 index.html。
    static Navigate(path := "/", hwnd := 0) {
        slot := this._Slot(hwnd)
        if !IsObject(slot)
            return {ok: false, reason: "尚未挂载"}
        if (path = "" || path = "/")
            path := "/index.html"
        try {
            slot.core.Navigate("https://" . slot.host . path)
            return {ok: true}
        } catch as e {
            return {ok: false, reason: e.Message}
        }
    }

    ; ─── 再挂一个目录到另一个虚拟主机 ─────────────────────────────────
    ; 页面在 app.local，笔记图片在 vault 下 —— markdown 里的 ./_assets/x.png
    ; 会被解析成 app.local/_assets/x.png（404）。把 vault 也挂成一个主机，
    ; 前端显示时加前缀、存盘时去掉，markdown 里就能保持可移植的相对路径。
    ;
    ; ⚠ 同一个 host 重复调用是覆盖语义（不报错），换 vault 不用先卸载 ✓
    ; ⚠ 与 Mount 一样必须传规范化路径，含 .. 时导航不报错、只出「无法访问此页面」。
    static MapHost(host, dir, hwnd := 0) {
        slot := this._Slot(hwnd)
        if !IsObject(slot)
            return {ok: false, reason: "尚未挂载"}
        if (host = "")
            return {ok: false, reason: "主机名为空"}
        dir := this._NormPath(dir)
        if !DirExist(dir)
            return {ok: false, reason: "目录不存在: " . dir}
        try {
            slot.core.SetVirtualHostNameToFolderMapping(host, dir, 1)
            return {ok: true, host: host, dir: dir}
        } catch as e {
            return {ok: false, reason: "映射虚拟主机失败: " . e.Message}
        }
    }

    ; ─── 把 AHK 对象暴露成 JS 的 chrome.webview.hostObjects.<name> ─────
    ; ⚠ hostObjects 是**按 WebView 实例**注册的：同一个 name 要在每个窗口各 Bind 一次，
    ;   不是挂一次全局生效（从前单例时期这个区别看不出来）。
    static Bind(name, obj, hwnd := 0) {
        slot := this._Slot(hwnd)
        if !IsObject(slot)
            return {ok: false, reason: "尚未挂载"}
        try {
            slot.core.AddHostObjectToScript(name, obj)
            return {ok: true}
        } catch as e {
            return {ok: false, reason: e.Message}
        }
    }

    ; ─── 在页面里执行 JS，同步等结果 ────────────────────────────────────
    ; 返回 {ok:true, value}（value 是 ExecuteScriptAsync 的原样返回，含 JSON 引号）
    ; ⚠ **JS 里抛异常不会让 ok 变 false**：ExecuteScriptAsync 对脚本异常只返回 null
    ;   （HTML 规范如此），所以「选择器写错」与「页面确实没有这个元素」看起来一样。
    ;   写断言时要么保证 JS 不抛错，要么在 JS 里自己 try/catch 后返回字符串。
    static Eval(js, hwnd := 0) {
        slot := this._Slot(hwnd)
        if !IsObject(slot)
            return {ok: false, reason: "尚未挂载"}
        try {
            raw := slot.core.ExecuteScriptAsync(js).await()
            if (raw = "" || raw = "null")
                return {ok: false, reason: "脚本返回 null（JS 语法错 / 抛异常 / 表达式无值）"}
            return {ok: true, value: raw}
        } catch as e {
            return {ok: false, reason: e.Message}
        }
    }

    ; ─── 轮询等待页面里的条件成立 ─────────────────────────────────────
    ; js 要返回真值（`window.x && ...` 这种即可）；超时返回 false。
    ; ⚠ 用 Sleep 轮询而不是等某个事件：WebView2 没有「页面脚本就绪」的回调，
    ;   而 ExecuteScriptAsync 在页面尚未加载时同样会正常返回，
    ;   只能靠反复问「那个对象有了吗」。
    static WaitFor(js, timeoutMs := 5000, intervalMs := 60, hwnd := 0) {
        t0 := A_TickCount
        loop {
            r := this.Eval(js, hwnd)
            if (r.ok && r.value != "" && r.value != "false" && r.value != "null")
                return true
            if (A_TickCount - t0 >= timeoutMs)
                return false
            Sleep intervalMs
        }
    }

    ; ─── 跟随父窗口尺寸 ─────────────────────────────────────────────────
    ; ⚠ 必须由调用方在父窗口的 Size 事件里点名调用 —— 不做挂钩，保持能力层无副作用
    static Resize(hwnd := 0) {
        slot := this._Slot(hwnd)
        if !IsObject(slot)
            return {ok: false, reason: "尚未挂载"}
        try {
            slot.ctrl.Fill()
            ; ⚠ 库只实现了 IsVisible 的 getter（ComCall 3），没有 putter。
            ;   而「在窗口隐藏期挂载」时 Chromium 会把自己留在隐藏状态：父窗口后来
            ;   重新显示也不回来（实测子窗口 vis=False、坐标 -32000,-32000）。
            ;   表现是「窗口出来了、编辑区一片纯底色」，看起来像 WebView2 根本没显示。
            ;   vtable 4 = put_IsVisible，这里补一次 TRUE。
            ComCall(4, slot.ctrl, "int", 1)
            return {ok: true}
        } catch as e {
            return {ok: false, reason: e.Message}
        }
    }

    static IsReady(hwnd := 0) {
        return IsObject(this._Slot(hwnd))
    }

    ; ─── 前端产物目录 ─────────────────────────────────────────────────
    ; 开发态在 <repo>\web\dist（src\ 的同级）；编译版与 exe 同级。
    ; 放能力层而不是某个模块里：笔记窗与面板都要它，谁都不该是「标准的来源」。
    static DistDir() {
        for p in [A_ScriptDir . "\..\web\dist", A_ScriptDir . "\web\dist"] {
            if DirExist(p)
                return this._NormPath(p)
        }
        return ""
    }

    ; ─── 路径规范化（展开 . / ..）────────────────────────────────────────
    static _NormPath(p) {
        if !p
            return p
        buf := Buffer(65536, 0)
        n := DllCall("kernel32\GetFullPathNameW", "wstr", p, "uint", 32767, "ptr", buf, "ptr", 0, "uint")
        return n ? StrGet(buf) : p
    }

    ; ─── 销毁 ───────────────────────────────────────────────────────────
    ; hwnd 省略 = 全部销毁（退出时用）。传 hwnd 只关那一个 —— 关面板不能顺手
    ; 把笔记窗的 Chromium 也带走，那正是单例时代的老毛病。
    static Destroy(hwnd := 0) {
        if hwnd {
            if !this._slots.Has(hwnd)
                return {ok: true}
            slot := this._slots[hwnd]
            try slot.ctrl.Close()
            this._slots.Delete(hwnd)
            if (this._cur = hwnd)
                this._cur := 0
            return {ok: true}
        }
        for h, slot in this._slots {
            try slot.ctrl.Close()
        }
        this._slots := Map()
        this._cur := 0
        return {ok: true}
    }
}
