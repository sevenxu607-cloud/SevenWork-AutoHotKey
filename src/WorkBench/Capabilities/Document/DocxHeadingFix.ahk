#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════════
;  DocxHeadingFix —— 让 pandoc 认得出 .docx 里的自定义标题样式（能力层 · 文档）
; ═══════════════════════════════════════════════════════════════════════════
; 背景：pandoc 的 docx reader 只把 `w:name` 为 `heading 1`..`heading 9` 的段落当标题。
;   国内课件 / 教辅常自定义「二级标题」「三级标题」「半括号标题（五级）」这类样式名 ——
;   它们在 Word 里有层级、有编号、导航窗格里一切正常，但 pandoc 一个标题都不输出，
;   整篇变成「嵌套有序列表」，落到 Markdown 编辑器里大纲是空的。
;   实测（2026-10-21，尚硅谷 NLP 课件 23MB，pandoc 3.11）：
;     原样式        → Header = 0（20088 行 AST 里一个都没有）
;     改成 heading N → Header = 215（##32 / ###55 / ####34 / #####53 / ######41，
;                      与 styles.xml 里 a0..a4 的使用次数逐项相等）
;
; 做法：**不改源文件**。复制一份到临时目录 → 改 word/styles.xml 里那几行 w:name →
;   重新打包 → 交给 pandoc。源文件零风险；本能力失败时调用方直接转原件。
;
; 只收路径与目录，不读 Config、不发事件、不写日志（能力层契约见 docs/CAPABILITIES.md）。
;
; ⚠ 为什么用 tar.exe 而不是 AHK 自带能力：AHK v2 没有 zip 支持。Windows 10 1803+
;   自带 bsdtar（C:\Windows\System32\tar.exe，实测 3.8.8），`-xf` 解 docx、
;   `-a -cf` 按扩展名打回 zip 都行，AHK 只需 RunWait 两条命令。
;   实测 23MB 课件：解压 148ms + 打包 760ms —— 每次转换都跑得起。
; ⚠ 输出 zip 必须放在**被打包目录之外** —— 放里面会把自己也打进去，越滚越大。
; ⚠ `-a` 靠扩展名选格式：先打成 .zip 再改名成 .docx；直接 `-cf x.docx` 会写成 tar 格式。
; ⚠ 反斜杠在 AHK 字符串里不是转义符（只有反引号是）。

class DocxHeadingFix {
    static TarExe := A_WinDir . "\System32\tar.exe"

    static StylesRel := "word\styles.xml"

    ; 中文数字 → 阿拉伯。只到九（heading 1..9 是 Word / pandoc 的上限）。
    static CnDigits := Map("一", 1, "二", 2, "三", 3, "四", 4
        , "五", 5, "六", 6, "七", 7, "八", 8, "九", 9)

    ; ═══ 主入口 ═══

    ; 产出一份「可以直接交给 pandoc」的 docx 副本，做两件事：
    ;   ① **把自动标题编号固化成文字**（DocxNumberFix）—— 否则 Word 的
    ;      「第 1 章 / 1.1 / 1）」这些模板编号在 Markdown 里整体消失；
    ;   ② 把自定义标题样式名规范化成 `heading N` —— 否则 pandoc 一个标题都不认。
    ;
    ;   src     源 .docx 绝对路径（不修改）
    ;   workDir 本次专用的空目录（调用方给，本能力会先删再建）
    ;
    ; 返回 {ok:true, path, changed, numbered, warnings, cleanup}
    ;        changed  = 实际改写的样式块数
    ;        numbered = 实际写入编号的标题段落数
    ;        warnings = 无法精确还原的说明（编号格式等），不阻断转换
    ;        cleanup  = true 表示 path / workDir / workDir.zip 是本次产物，调用方用完要删
    ;      {ok:false, reason}
    ;        reason: bad-arg / no-tar / no-workdir / no-extract / no-styles / no-pack
    static Prepare(src, workDir) {
        if (src = "" || workDir = "")
            return {ok: false, reason: "bad-arg"}
        if !FileExist(this.TarExe)
            return {ok: false, reason: "no-tar"}

        ; 每次一个全新目录：用户连按两次也不会互相踩。
        try DirDelete(workDir, true)
        try DirCreate(workDir)
        catch
            return {ok: false, reason: "no-workdir"}

        if !this._Extract(src, workDir)
            return {ok: false, reason: "no-extract"}

        stylesPath := workDir . "\" . this.StylesRel
        if !FileExist(stylesPath)
            return {ok: false, reason: "no-styles"}

        ; 读 → 改 → 写。中文样式名要 UTF-8；读用 "UTF-8"（自动跳过 BOM），
        ; 写回用 "UTF-8-RAW"（无 BOM，与源文件一致 —— 别给 pandoc 添新变量）。
        changedStyles := 0
        numbered := 0
        warnings := []
        try {
            xml := FileRead(stylesPath, "UTF-8")

            ; ⚠ **顺序不能反**：编号固化要靠「样式名 → 标题级别」来判断哪些段落是标题，
            ;   而「半括号标题（五级）」这类名字一旦先被改成 `heading 5`，
            ;   LevelOf() 就认不出来（它把标准名当「无需处理」返回 0），
            ;   这些标题的编号会静默漏掉。所以先固化编号，再删样式编号，最后改样式名。
            fix := this._FixNumbers(workDir, xml, warnings)
            numbered := fix.count

            ; 编号已写进文字，样式上的 numPr 必须去掉 —— 否则 pandoc 仍把标题当
            ; 有序列表（实测：不删的结果是整篇「1. NLP导论 / 1. 定义」，零标题）。
            ; ⚠ 但**固化失败时不能删**：编号没进文字，再删掉 numPr 等于把
            ;   「有编号的标题」变成「没编号的标题」，比原样交给 pandoc 丢得更多。
            stripped := 0
            if !fix.failed {
                strip := DocxNumberFix.StripStyleNumbering(xml)
                if (strip.stripped > 0) {
                    xml := strip.xml
                    stripped := strip.stripped
                }
            }

            fixed := this.FixStyles(xml)
            if (fixed.count > 0 || stripped > 0) {
                f := FileOpen(stylesPath, "w", "UTF-8-RAW")
                f.Write(fixed.xml)
                f.Close()
                changedStyles := fixed.count + stripped
            }
        } catch as e
            ; detail 带出真实异常 —— 只给 reason 的话，一句 no-styles 完全看不出
            ; 是读文件、编号固化还是样式改名出的问题（实测排查花了一轮）。
            return {ok: false, reason: "no-styles", detail: e.Message}

        ; 两件事都没改 → 直接把原件交给 pandoc，省掉一次打包。
        if (changedStyles = 0 && numbered = 0)
            return {ok: true, path: src, changed: 0, numbered: 0
                , warnings: warnings, cleanup: false}

        outZip := workDir . ".zip"
        outDocx := workDir . ".docx"
        ; 旧产物先删 —— tar 对已存在的同名包是**追加**，留着会打出一堆重复条目。
        try FileDelete(outZip)
        try FileDelete(outDocx)

        if !this._Pack(workDir, outZip)
            return {ok: false, reason: "no-pack"}
        try FileMove(outZip, outDocx, true)
        catch
            return {ok: false, reason: "no-pack"}

        return {ok: true, path: outDocx, changed: changedStyles
            , numbered: numbered, warnings: warnings, cleanup: true}
    }

    ; 把自动标题编号固化成文字，写回 document.xml。
    ;
    ; stylesXml 传**改写前**的原文 —— 见 Prepare 里「顺序不能反」那段。
    ; numbering.xml 不存在（文档完全没用编号）时直接跳过，不算失败。
    ; 返回实际写入编号的段落数；任何异常都吞掉并返回 0（编号是增强，不该阻断转换）。
    ;
    ; ⚠ warnings 是**普通参数**，不能写成 `&warnings`：AHK v2 的 ByRef 参数
    ;   要求「变量引用」，而数组本身已经是引用 —— 实测传数组会抛
    ;   `Parameter #3 ... requires a variable reference, but received an Array`，
    ;   异常又被外层 try 吞成一句 no-styles，排查时完全看不出是哪一步坏的。
    ; 返回 {count, failed}
    ;   count  = 实际写入编号的标题段落数
    ;   failed = true 表示固化出错（此时 count 必为 0）；调用方据此**不要**清样式编号
    static _FixNumbers(workDir, stylesXml, warnings) {
        docPath := workDir . "\word\document.xml"
        numPath := workDir . "\word\numbering.xml"
        if !FileExist(docPath) || !FileExist(numPath)
            return {count: 0, failed: false}
        try {
            docXml := FileRead(docPath, "UTF-8")
            numXml := FileRead(numPath, "UTF-8")
            r := DocxNumberFix.FixDocument(docXml, stylesXml, numXml)
            if !r.ok {
                warnings.Push("编号固化未能启动：" . (r.HasProp("reason") ? r.reason : "?"))
                return {count: 0, failed: true}
            }
            if (r.numbered > 0) {
                f := FileOpen(docPath, "w", "UTF-8-RAW")
                f.Write(r.xml)
                f.Close()
            }
            for w in r.warnings {
                if !this._HasText(warnings, w)
                    warnings.Push(w)
            }
            return {count: r.numbered, failed: false}
        } catch as e {
            warnings.Push("编号固化失败：" . e.Message)
            return {count: 0, failed: true}
        }
    }

    static _HasText(arr, msg) {
        for v in arr {
            if (v = msg)
                return true
        }
        return false
    }

    ; ═══ styles.xml 改写 ═══

    ; 把「N级标题」这类段落样式名换成 pandoc 认得的 `heading N`。
    ; 返回 {xml, count}。count = 0 时 xml 原样返回。
    ;
    ; 只认 `w:type="paragraph"` —— 字符样式（character）即使叫「三级标题」也不该变标题。
    ; `<w:name>` 在 Word 生成的 styles.xml 里总是紧跟 `<w:style ...>` 之后，
    ; 所以一条正则就能同时拿到「这是个段落样式」和「它叫什么」。
    static FixStyles(xml) {
        pat := '(?i)<w:style\b[^>]*?w:type="paragraph"[^>]*?>\s*<w:name\s+w:val="([^"]*)"'
        out := ""
        last := 1
        count := 0
        pos := 1
        while (p := RegExMatch(xml, pat, &m, pos)) {
            level := this.LevelOf(m[1])
            if (level = 0) {
                ; 不用改的段落样式：跳过（pos 必须前移，否则死循环）
                pos := p + StrLen(m[0])
                continue
            }
            ; m[0] 形如 `<w:style ...><w:name w:val="三级标题"` ——
            ; 替换末尾那个值，前面的标签一个字不动。
            valPos := InStr(m[0], 'w:val="', false, -1) + 7
            newBlock := SubStr(m[0], 1, valPos - 1) . "heading " . level
                . SubStr(m[0], valPos + StrLen(m[1]))
            out .= SubStr(xml, last, p - last) . newBlock
            last := p + StrLen(m[0])
            pos := last
            count++
        }
        if (count = 0)
            return {xml: xml, count: 0}
        return {xml: out . SubStr(xml, last), count: count}
    }

    ; 样式名 → 标题级别；返回 0 表示「不是标题样式」或「已经是标准名」。
    ;
    ;   「二级标题」               → 2
    ;   「圆括号标题（六级标题）」  → 6   （先命中「六级标题」）
    ;   「半括号标题（五级）」      → 5   （没有「级标题」，靠「（五级」兜住）
    ;   「标题 3」/「标题3」        → 3
    ;   「heading 2」/「Heading 2」 → 0   （已经是标准名，不动）
    static LevelOf(name) {
        if RegExMatch(name, 'i)^\s*heading\s*[1-9]\s*$')
            return 0
        if RegExMatch(name, '([一二三四五六七八九])级标题', &m)
            return this.CnDigits[m[1]]
        if RegExMatch(name, '（\s*([一二三四五六七八九])级', &m)
            return this.CnDigits[m[1]]
        if RegExMatch(name, '^\s*标题\s*([1-9])\s*$', &m)
            return Integer(m[1])
        return 0
    }

    ; ═══ tar 两条命令 ═══

    static _Extract(src, dir) {
        cmd := '"' . this.TarExe . '" -xf "' . src . '" -C "' . dir . '"'
        try code := RunWait(cmd, , "Hide")
        catch
            return false
        return (code = 0)
    }

    static _Pack(dir, zipPath) {
        ; ⚠ 必须用 `*`，**不能**用 `.`：`.` 打出来的条目名带 `./` 前缀
        ;   （`./word/media/image1.png`），而 OPC 包内路径是 `word/media/...`。
        ;   pandoc 照样读得到 document.xml，却找不到图片 —— `--extract-media` 时
        ;   **静默丢图**（实测 145 张一张不剩，md 里连 `![]` 都没有，退出码仍是 0）。
        ;   换成 `*` 由 bsdtar 自己展开，条目名干净，144 张图正常抽出。
        ; `-a` 按 .zip 扩展名选 zip 格式；`-C dir` 先切目录，所以 `*` 只匹配包内顶层。
        cmd := '"' . this.TarExe . '" -a -cf "' . zipPath . '" -C "' . dir . '" *'
        try code := RunWait(cmd, , "Hide")
        catch
            return false
        return (code = 0) && FileExist(zipPath)
    }
}
