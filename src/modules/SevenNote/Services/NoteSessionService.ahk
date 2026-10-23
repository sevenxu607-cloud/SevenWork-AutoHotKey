#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════════
;  NoteSessionService —— 「当前这篇笔记」的会话状态
; ═══════════════════════════════════════════════════════════════════════════
;  读写从前散在 LoadFeature / SaveFeature 里，各自现摸 State.GetDate()，
;  「日期已经改成新的一天、正文还是旧的」这种半成品状态没人负责。这个服务就是
;  那个负责人 —— 当前日期 / 实际路径 / 是否已载入，三样只有一个出处：
;
;    · Open(date)  换文档：读文件 → 推给编辑器 → **前端确认接收之后**才提交日期；
;    · Save()      落盘：返回明确结果，调用方据此决定能不能切日期 / 退出；
;    · Reset()     丢掉会话（窗口重建、页面重导航时用）。
;
;  ⚠ 位置：Service 层（可读 Config / State、可发事件），**不认识任何 Feature**。
;    Feature 之间「先存盘再切走」因此不必互相调用 —— 都调这里。
;  ⚠ 本服务自己不订阅事件：订阅是 Feature 的活，服务只提供动作与结果。
; ═══════════════════════════════════════════════════════════════════════════

class NoteSessionService {
    ; 当前打开的是哪一天。"" = 还没载入过。
    static _docDate := ""
    ; 当前这篇在磁盘上的实际路径（可能带标签）。"" = 该日期还没有文件。
    static _docPath := ""
    ; 是否已完成一次**真正的**载入。false 时 TakeMarkdown() 一律返回空串，
    ; 于是整条保存链路自己就停住了 —— 不会拿页面里剩下的东西覆盖用户的笔记。
    static _docLoaded := false

    static GetDate() => this._docDate
    static GetPath() => this._docPath
    static IsLoaded() => this._docLoaded

    static Reset() {
        this._docDate := ""
        this._docPath := ""
        this._docLoaded := false
    }

    ; ═══ 换文档 ═══
    ; 返回 {ok:true, created, unchanged} | {ok:false, reason}
    ;   created   = 该日期本来没有笔记，本次给的是速记题头
    ;   unchanged = 已经是这一天且载入完成，什么都没做
    ; ⚠ 调用方负责先把当前这篇存盘（Save()）—— 这里不替别人做决定。
    ; ⚠ 载入**失败**时日期一动不动：从前是先把 State 改掉再推正文，推失败就
    ;   变成「标题是新的一天、屏幕是旧内容」，接着一保存就把新日期写成了旧正文。
    static Open(date) {
        if (date = "")
            return {ok: false, reason: "bad-date"}

        ; 同一天不重推：重推会冲掉用户此刻的光标与撤销栈，
        ; 观感就是「按了跳转，字跳回文首」。
        if (this._docLoaded && date = this._docDate)
            return {ok: true, created: false, unchanged: true}

        src := this._Read(date)
        if !src.ok
            return src

        pushed := this.PushMarkdown(src.md)
        if !pushed.ok
            return {ok: false, reason: pushed.reason}

        ; —— 到这里才算真的换过去了 ——
        this._docDate := date
        this._docPath := src.path
        this._docLoaded := true
        State.SetDate(date)
        return {ok: true, created: src.created, unchanged: false}
    }

    ; ═══ 落盘 ═══
    ; 返回 {ok:true, path, unchanged?, empty?} | {ok:false, reason, recoverable?}
    ;   recoverable: true = 「当前没有可丢的内容」，调用方可以继续切日期。
    ;   unchanged / empty 都算成功 —— 什么都没变本来就不需要写盘。
    static Save() {
        r := ""
        try
            r := this._DoSave()
        catch as e
            r := {ok: false, reason: e.Message}
        this._Report(r)
        return r
    }

    ; 结果广播：热键 / 自动保存 / 切日期 / 收起窗口，所有保存路径共用这一份口径 ——
    ; 从前每处各发一遍，迟早有一处说「已保存」而另一处什么也不说。
    ; `Note.Status` 只给笔记窗口的底栏用（带 text / kind），与其他模块无关。
    static _Report(r) {
        if r.ok {
            if r.HasProp("empty") {
                EventBus.Emit("Save.Completed"
                    , {time: FormatTime(, "HH:mm"), empty: true})
                EventBus.Emit("Note.Status", {text: "空笔记不落盘", kind: "info"})
            } else if r.HasProp("unchanged") {
                EventBus.Emit("Save.Completed"
                    , {time: FormatTime(, "HH:mm"), unchanged: true})
                EventBus.Emit("Note.Status", {text: "无改动", kind: "info"})
            } else {
                EventBus.Emit("Save.Completed", {time: FormatTime(, "HH:mm")})
                EventBus.Emit("Note.Status"
                    , {text: "已保存 " . FormatTime(, "HH:mm"), kind: "ok"})
            }
            return
        }

        ; 「尚未载入 / 页面未就绪」是冷启动的正常状态，不是故障 ——
        ; 每次都上报会把真错误淹掉。其余失败一律上报，并在底栏说清楚。
        if (r.HasProp("recoverable") && r.recoverable)
            return
        EventBus.Emit("Error.Occurred", {msg: "保存失败：" . r.reason})
        EventBus.Emit("Note.Status", {text: "保存失败：" . r.reason, kind: "err"})
    }

    static _DoSave() {
        if !this._docLoaded
            return {ok: false, reason: "尚未载入笔记", recoverable: true}
        date := this._docDate
        if (date = "")
            return {ok: false, reason: "尚未载入笔记", recoverable: true}

        hwnd := State.GetGuiHwnd()
        if !hwnd || !WebHostService.IsReady(hwnd)
            return {ok: false, reason: "页面未就绪", recoverable: true}

        md := this.TakeMarkdown()
        if (md = "") {
            ; ⚠ 这里**不能**标 recoverable：页面在、但取不回正文，
            ;   用户可能刚写了一大段。宁可这次不写、也不许切走。
            return {ok: false, reason: "取不到正文"}
        }

        ; 空笔记不落盘，且顺手清掉当天已有的 .md（与旧版语义一致）
        if NoteStoreService.IsEmptyNote(md, date) {
            p := NoteStoreService.FindMd(date)
            if (p != "" && FileExist(p))
                try FileDelete(p)
            this._docPath := ""
            return {ok: true, empty: true}
        }

        ; 先查后存（保留带标签的文件名）
        mdPath := this._docPath
        if (mdPath = "")
            mdPath := NoteStoreService.FindMd(date)
        if (mdPath = "")
            mdPath := NoteStoreService.DefaultMdPath(date)

        ; ⚠ 内容没变就一个字节都不写。
        ;   Milkdown 序列化会把 CRLF 规范成 LF、把 Obsidian 的冗余转义 `\#`
        ;   还原成 `#`（实测最长一篇 11813 → 11151 字符，差额 = 567 个 CR + 95 处转义）。
        ;   语义等价，但「打开看一眼历史笔记」不该改写它的文件。
        if FileExist(mdPath) {
            try {
                if (FileRead(mdPath, "UTF-8") = md)
                    return {ok: true, path: mdPath, unchanged: true}
            }
        }

        if !NoteStoreService.WriteFile(mdPath, md, "UTF-8")
            return {ok: false, reason: "无法写入 " . mdPath}

        this._docPath := mdPath
        return {ok: true, path: mdPath}
    }

    ; ═══ 只读一天（不碰编辑器）═══
    ; 给「看一眼有没有这篇」这类查询用，返回 {ok, md, path, created} | {ok:false, reason}
    static ReadOnly(date) => this._Read(date)

    ; ═══ 取编辑器里的存储态 Markdown ═══
    ; 未载入 / 窗口没挂 / 页面未就绪 / JS 取不到 → 空串，调用方据此跳过保存。
    ; ⚠ 一律显式传 hwnd：WebHostService 是多实例的，无参会落到「最近挂载的窗口」上 ——
    ;   面板或提示词库一开，笔记这边就会去问另一个页面的正文。
    static TakeMarkdown() {
        if !this._docLoaded
            return ""
        hwnd := State.GetGuiHwnd()
        if !hwnd || !WebHostService.IsReady(hwnd)
            return ""
        r := WebHostService.Eval("(()=>{try{const m=window.__swnote.getMarkdown();"
            . "return (typeof m==='string')?m:''}catch(e){return ''}})()", hwnd)
        if !r.ok
            return ""
        return JsText.Unquote(r.value)
    }

    ; ═══ 把正文推进编辑器 ═══
    ; 返回 {ok:true} | {ok:false, reason}
    ;
    ; ⚠ 必须等编辑器就绪：首次呼出时 WebView2 还在加载 Vite 产物，
    ;   window.__swnote 尚且不存在，setMarkdown 会静默落空（画面停在空白）。
    ;   App.vue 里虽然也有 pendingMd 兜底，但那要等 @ready 才补灌 ——
    ;   切日期时编辑器早就 ready 了，走的不是那条路，所以这里得自己等。
    ; ⚠ 必须认前端返回值：只有 'ok' 才是真换上了。
    ;   'pending:*' = 编辑器还没建好（页面里挂成了待灌内容），
    ;   'ERR *'     = 换文档时抛错。两者都当失败处理 ——
    ;   否则日期提交了、正文还是旧的那一篇，之后一保存就把旧正文写到新日期上。
    static PushMarkdown(md) {
        hwnd := State.GetGuiHwnd()
        if !hwnd
            return {ok: false, reason: "窗口未创建"}
        if !WebHostService.WaitFor(
            "window.__swnote && typeof window.__swnote.setMarkdown === 'function'"
            , 8000, 60, hwnd)
            return {ok: false, reason: "编辑器未就绪"}

        r := WebHostService.Eval("window.__swnote.setMarkdown("
            . JsText.Escape(md) . ")", hwnd)
        if !r.ok
            return {ok: false, reason: r.reason}

        verdict := JsText.Unquote(r.value)
        if (verdict != "ok")
            return {ok: false, reason: "编辑器未接受：" . verdict}
        return {ok: true}
    }

    ; ═══ 读一天的正文 ═══
    ; 返回 {ok:true, md, path, created} | {ok:false, reason}
    ;
    ; ⚠ 三种情况必须分开，别混成一个空串：
    ;   ① 没有文件       → 给速记题头（created=true），这是「新建」；
    ;   ② 有文件读不出来 → **失败**。从前这里静默回退成空笔记头，
    ;      接着一存就把那一篇覆盖成一行标题 —— 40 行笔记换一行字。
    ;   ③ 有文件且读到   → 原样返回。
    static _Read(date) {
        path := NoteStoreService.FindMd(date)
        if (path = "")
            return {ok: true, md: NoteStoreService.EmptyNoteHeader(date)
                , path: "", created: true}

        try
            md := FileRead(path, "UTF-8")
        catch as e
            return {ok: false, reason: "读取失败：" . path . " / " . e.Message}

        ; 0 字节文件当新建处理：它本来就没有内容可保护。
        if (md = "")
            md := NoteStoreService.EmptyNoteHeader(date)

        return {ok: true, md: md, path: path, created: false}
    }
}
