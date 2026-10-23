#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════════
;  FileConvertService —— 选中的文件 → 同级同名 .md（模块：Folders）
; ═══════════════════════════════════════════════════════════════════════════
; 只做策略：不碰窗口、不发事件、不弹提示。
;   · 输出路径怎么定、哪些该跳过、批量怎么编排，都在这儿；
;   · 真正调 pandoc 的是能力层 PandocRunner；给用户看的提示在 ConvertFeature。
;
; 跳过规则（Plan 的顺序即优先级，都返回 {path, reason}）：
;   bad-path      空路径 / 文件不存在
;   is-folder     选中的是文件夹（本功能只转文件，不递归）
;   is-markdown   源文件本身就是 .md（自己转自己）
;   unsupported   pandoc 读不了的输入格式（pdf / doc）
;   no-extension  没有扩展名（pandoc 无从推断输入格式）
;   exists        同级已有同名 .md
;
; ⚠ **已存在就跳过，绝不覆盖**：同名 md 很可能是人手写的笔记，覆盖是破坏性操作。
;   想重转，删掉旧的再按一次 Alt+M 即可（用户 2026-10-21 选定的方案）。
; ⚠ 图片抽到同级 `<文件名>_media\`。pandoc 默认把链接写成**绝对路径**，转完由
;   _RelativizeMedia 改成相对链接 —— md 与 _media 目录成对搬运即可，换机器不丢图。
; ⚠ 本类是 Service 层，读 Config 是允许的（架构：Service 可读 Config / State）。

class FileConvertService {
    ; pandoc 读不了的输入格式。依据：本机 pandoc 3.11 的 --list-input-formats 里
    ; **没有 pdf、也没有 doc**（老式二进制 Word）。提前判掉，给一句人话；
    ; 交给 pandoc 自己失败，用户只会看到一行看不懂的英文。
    static Unsupported := ["pdf", "doc"]

    static MediaSuffix := "_media"

    ; ═══ 主入口 ═══

    ; 把选中的路径逐个转成同名 .md。
    ; 返回 {done: [目标路径...], skipped: [{path, reason}]
    ;       , failed: [{path, reason, code, detail}]
    ;       , warnings: [{path, msg}]}
    ;   warnings = 转换成功、但有「没能完全还原」的地方（如不认识的编号格式）。
    static ConvertMany(paths) {
        result := {done: [], skipped: [], failed: [], warnings: []}
        if !IsObject(paths) || paths.Length = 0
            return result

        cmd := PandocRunner.ResolveCmd(Config.PandocPath)

        for src in paths {
            plan := this.Plan(src)
            if !plan.ok {
                result.skipped.Push({path: src, reason: plan.reason})
                continue
            }

            ; docx 先过一道「标题样式名规范化」：pandoc 只认 `heading N`，而国内课件常用
            ; 「二级标题 / 三级标题 / 半括号标题（五级）」这类自定义名 —— 直接转的话一个标题
            ; 都没有，整篇变成嵌套有序列表（实测 23MB NLP 课件：0 个标题 → 223 个）。
            ; 失败 / 无可改样式时原样转源文件，转换照常进行。
            prep := this._Prepare(plan)

            ; pandoc 失败时也可能先建出空的 _media 目录。把「转换前有没有」记下来，
            ; 失败且本来没有就删掉 —— 别在用户的目录里留个空壳。
            hadMedia := DirExist(plan.mediaDir)
            ; try/finally：Convert 抛错（RunWait 起不来之类）也要把临时副本删掉。
            ; 少这一层的话，一次异常就在 Temp 里留一整个解压目录 —— 实测崩溃一次
            ; 留下 180 个文件、21MB。
            try {
                r := PandocRunner.Convert(cmd, prep.src, plan.dst, plan.mediaDir)
            } finally {
                this._CleanupPrepared(prep)
            }
            if r.ok {
                this._RelativizeMedia(plan.dst, plan.mediaDir, plan.stem . this.MediaSuffix)
                result.done.Push(plan.dst)
                ; 编号固化是「增强」：个别格式没还原到位不该让整次转换失败，
                ; 但必须让用户看见 —— 否则他会把 Markdown 里那串序号当成原文。
                for w in prep.warnings
                    result.warnings.Push({path: src, msg: w})
                ; 合并单元格在 Markdown 里表达不了，pandoc 会退回 <table> HTML。
                ; 内容不丢，但编辑器多半不渲染 —— 必须说出来，别让用户以为
                ; 「表格转完了却看不见」是自己操作错了。
                if this._HasHtmlTable(plan.dst)
                    result.warnings.Push({path: src
                        , msg: "含合并单元格的表格已输出为 <table> HTML（编辑器可能不渲染）"})
                continue
            }
            if (!hadMedia && DirExist(plan.mediaDir)) {
                try DirDelete(plan.mediaDir, true)
            }
            result.failed.Push({path: src, reason: r.reason
                , code: r.HasProp("code") ? r.code : 0
                , detail: this._DetailOf(r)})
        }
        return result
    }

    ; ═══ 单个文件的处理计划 ═══

    ; 返回 {ok:true, src, dst, stem, mediaDir} 或 {ok:false, reason}
    static Plan(src) {
        if (src = "")
            return {ok: false, reason: "bad-path"}
        if DirExist(src)
            return {ok: false, reason: "is-folder"}
        if !FileExist(src)
            return {ok: false, reason: "bad-path"}

        ; ⚠ SplitPath 的输出参数顺序是 (&FileName, &Dir, &Ext, &NameNoExt) ——
        ;   **不是** (&Dir, &Name, &Ext)。写错过一次，实测 dst 直接拼成
        ;   `sample.docx\C:\...\convtest.md`：第一个变量拿到文件名、第二个拿到目录，
        ;   pandoc 于是以「目标路径不存在」退出 1，而代码看上去毫无问题。
        ;   要么按位置传全，要么用 `SplitPath(path, , &dir, &ext, &stem)` 把前一个空出来。
        SplitPath(src, , &dir, &ext, &stem)
        ; ⚠ Ext 也**不带点**（"DOCX" 而不是 ".DOCX"）—— 实测踩过：写成 SubStr(ext, 2)
        ;   会把 "pdf" 削成 "df"，于是 unsupported / is-markdown 全都不命中，
        ;   .pdf 一路走到 pandoc 才失败，提示还变成了「pandoc 报错」。
        extRaw := StrLower(ext)
        if (extRaw = "md")
            return {ok: false, reason: "is-markdown"}
        if (extRaw = "")
            return {ok: false, reason: "no-extension"}
        for bad in this.Unsupported {
            if (extRaw = bad)
                return {ok: false, reason: "unsupported"}
        }

        ; SplitPath 的目录部分**不含**末尾反斜杠，但盘根（D:\）例外 ——
        ; 直接加 "\" 会拼出 "D:\\a.md"，虽然多数 API 能容忍，但没必要留着。
        sep := (SubStr(dir, -1) = "\") ? "" : "\"
        dst := dir . sep . stem . ".md"
        if FileExist(dst)
            return {ok: false, reason: "exists"}

        return {ok: true, src: src, dst: dst, stem: stem
            , ext: extRaw, mediaDir: dir . sep . stem . this.MediaSuffix}
    }

    ; ═══ docx 预处理 ═══

    ; 返回 {src, tmpBase, numbered, warnings}
    ;   tmpBase 非空表示 src 是临时副本，用完要 _CleanupPrepared()。
    ;   numbered = 固化了编号的标题段落数；warnings = 无法精确还原的说明。
    ; 只对 .docx 动手 —— 别的格式没有 word/styles.xml / numbering.xml 可改
    ; （odt 的样式在 content.xml，规则完全不同，暂不处理）。
    ;
    ; ⚠ 字段名**不能叫 `base`**：AHK v2 的对象字面量里 `base:` 是「设置原型」的保留键，
    ;   `{src: x, base: "C:\..."}` 直接抛 `Invalid base.`（实测踩到）。
    static _Prepare(plan) {
        if (plan.ext != "docx")
            return {src: plan.src, tmpBase: "", numbered: 0, warnings: []}
        tmpBase := A_Temp . "\SevenWork\docxfix\" . A_TickCount . "_" . Random(1000, 9999)
        try r := DocxHeadingFix.Prepare(plan.src, tmpBase)
        catch {
            ; 能力层自己抛错（属于 bug 级）时，别把整个解压目录留在 Temp 里 ——
            ; 此时 ConvertMany 的 finally 还没接上，垃圾只能在这儿清。
            this._CleanupPrepared({tmpBase: tmpBase})
            return {src: plan.src, tmpBase: "", numbered: 0, warnings: []}
        }
        if !r.ok || !r.cleanup {
            ; 预处理没改成任何东西 → 用原件，但警告仍要带出去
            ; （例如「编号格式未完全还原」时编号算是改过了，走不到这里；
            ;   这里主要覆盖 no-extract / no-pack 这类彻底失败的兜底）。
            this._CleanupPrepared({tmpBase: tmpBase})
            return {src: plan.src, tmpBase: ""
                , numbered: r.HasProp("numbered") ? r.numbered : 0
                , warnings: r.HasProp("warnings") ? r.warnings : []}
        }
        return {src: r.path, tmpBase: tmpBase
            , numbered: r.HasProp("numbered") ? r.numbered : 0
            , warnings: r.HasProp("warnings") ? r.warnings : []}
    }

    ; 删掉 _Prepare 留下的三样东西：解压目录、同名 .zip、同名 .docx。
    ; 三个 try 各自独立 —— 打包中途失败时可能只存在其中一两个。
    static _CleanupPrepared(prep) {
        if (prep.tmpBase = "")
            return
        try DirDelete(prep.tmpBase, true)
        try FileDelete(prep.tmpBase . ".zip")
        try FileDelete(prep.tmpBase . ".docx")
    }

    ; ═══ 收尾 ═══

    ; pandoc 的 --extract-media 把图片链接写成**绝对路径**（实测：
    ; `![alt](C:\...\picdoc_media/media/rId9.png)`）—— md 一旦挪走 / 发给别人，
    ; 图就全断了，而「Markdown 可以整包搬走」正是这份产物的用处。
    ; 转完把那个绝对前缀换成目录名（`picdoc_media/media/rId9.png`），
    ; 让 md 与 _media 目录成对搬运即可。没有图片时 pandoc 不建目录、文本里也没有
    ; 这个前缀，替换自然是空操作。
    static _RelativizeMedia(mdPath, mediaDir, mediaName) {
        if !FileExist(mdPath)
            return
        try txt := FileRead(mdPath, "UTF-8")
        catch
            return
        if (txt = "")
            return
        newTxt := StrReplace(txt, mediaDir, mediaName)
        if (newTxt = txt)
            return
        ; ⚠ 用 FileOpen("w") 原地覆盖，别 FileDelete + FileWrite —— 中间失败就什么都没了。
        try {
            f := FileOpen(mdPath, "w", "UTF-8")
            f.Write(newTxt)
            f.Close()
        }
    }

    ; ═══ 小工具 ═══

    ; 转换结果里有没有 <table> 原始 HTML（= 有表格用了 Markdown 表达不了的合并单元格）。
    ; 只读文本，不解析 HTML —— 我们要回答的只是「有没有降级」。
    static _HasHtmlTable(mdPath) {
        if !FileExist(mdPath)
            return false
        try txt := FileRead(mdPath, "UTF-8")
        catch
            return false
        return InStr(txt, "<table") > 0
    }

    ; 失败原因里的那一行 pandoc 原文（可能不存在：no-output 分支就没有 detail）
    static _DetailOf(r) {
        if !r.HasProp("detail")
            return ""
        return r.detail
    }
}
