#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════════
;  DocxNumberFix —— 把 DOCX 的自动标题编号固化成文字（能力层 · 文档）
; ═══════════════════════════════════════════════════════════════════════════
; 背景：Word / WPS 的「第 1 章 / 1.1 / 1.1.1 / 1）」这类编号通常**不是正文文字**，
;   而是「样式 → numPr → numbering.xml 的多级模板」渲染出来的。pandoc 的 docx
;   reader 只取段落文字，模板里的编号于是整体消失 —— 标题层级还在（`##`），
;   编号全没了。实测（2026-10-23，尚硅谷 NLP 课件 23MB / pandoc 3.11）：
;     源规则：第 %1 章 / %1.%2 / %1.%2.%3 / %1.%2.%3.%4 / %5） / （%6）
;     转换后：# NLP导论 / ## 定义 / ### 文本分类 …… 一个编号都不剩
;
; 做法：**在临时副本上**、转 pandoc 之前，把编号算出来写进标题文字。
;   源文件一个字都不动，本能力只收字符串、返回字符串。
;
; ⚠ 只处理**标题样式**上的编号。普通项目符号 / 编号列表不碰 ——
;   Markdown 有列表语法，pandoc 会正确转成 `-` / `1.`；固化反而把列表压平成正文。
; ⚠ `w:numId=0` 是「显式取消编号」（Word 里手动去掉某一段的编号）。遇到它
;   **不补号、也不推进计数** —— 否则本没有编号的标题会突然冒出序号，
;   后面的计数还会整体错位（实测样本里有「完整案例如下：」就是这个情况）。
; ⚠ 编号规则按**原模板**逐级还原，不按 Markdown 的 `#` 数量重新生成 ——
;   章节重启、附录编号、`（1）` 这类写法只能从原模板得到。
; ⚠ 反斜杠在 AHK 字符串里不是转义符（只有反引号是）。
; ═══════════════════════════════════════════════════════════════════════════

class DocxNumberFix {
    ; 中文小写数字（chineseCounting），只到 99 —— 标题级别用不到更大。
    static CnDigits := ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九"]

    ; ═══ 主入口 ═══
    ;
    ; docXml / stylesXml / numXml 是三份 XML 的原文（UTF-8 解码后的字符串）。
    ; 返回 {ok:true, xml, numbered, skipped, warnings}
    ;   numbered = 实际写入编号的标题段落数
    ;   skipped  = 有编号规则但没写成（空段落 / 没有 w:t）
    ;   warnings = 无法精确还原时的说明（不会打断转换）
    ;      {ok:false, reason} —— bad-arg
    static FixDocument(docXml, stylesXml, numXml) {
        if (docXml = "" || stylesXml = "" || numXml = "")
            return {ok: false, reason: "bad-arg"}

        styleMap := this._ParseStyles(stylesXml)
        numMap := this._ParseNumbering(numXml)
        if (numMap.Count = 0)
            return {ok: true, xml: docXml, numbered: 0, skipped: 0, warnings: []}

        counters := Map()      ; numId → 9 级计数器
        warnings := []
        numbered := 0
        skipped := 0

        out := ""
        last := 1
        pos := 1
        ; `(?s)` 让 `.` 跨行：document.xml 是单行还是带缩进都要能匹配。
        ; 段落之间**不会**嵌套 `w:p`，所以非贪婪匹配到第一个 `</w:p>` 是安全的。
        while (p := RegExMatch(docXml, "(?s)<w:p\b[^>]*>.*?</w:p>", &m, pos)) {
            para := m[0]
            ; ⚠ 原始长度要单独存：下面 _ClearNumbering 会改写 para（插入 numPr），
            ;   若用改后的长度推进 last，后续切片全部错位 —— 产出的 docx 结构损坏，
            ;   pandoc 只给一句 `couldn't parse docx file: DocxError`，看不出是这里。
            paraLen := StrLen(para)
            pos := p + paraLen

            ; ─── 这一段是标题吗 ───
            styleId := ""
            if RegExMatch(para, '<w:pStyle\s+w:val="([^"]+)"', &sm)
                styleId := sm[1]
            if (styleId = "" || !styleMap.Has(styleId))
                continue
            info := styleMap[styleId]
            if !info.title
                continue

            ; ─── 用哪套编号、第几级 ───
            numId := info.numId
            ilvl := info.ilvl

            ; 段落直接设置的 numPr 覆盖样式（Word 的实际优先级）。
            if RegExMatch(para, "(?s)<w:numPr>.*?</w:numPr>", &npm) {
                if RegExMatch(npm[0], '<w:numId\s+w:val="(\d+)"', &nm)
                    numId := Integer(nm[1])
                if RegExMatch(npm[0], '<w:ilvl\s+w:val="(\d+)"', &im)
                    ilvl := Integer(im[1])
            }

            ; numId = 0 是「显式取消编号」：不补号、**不推进计数**。
            if (numId = "" || numId = 0)
                continue
            if (ilvl < 0 || ilvl > 8)
                ilvl := 0

            if !numMap.Has(numId)
                continue
            abs := numMap[numId]
            if !abs.levels.Has(ilvl)
                continue
            lvl := abs.levels[ilvl]

            ; ─── 推进计数 ───
            ; Word 的规则：本级 +1，比它更深的级全部归零。
            ; 不归零的话「2.1」后面接一个新的一级标题，下一个二级会变成「2.2」而不是「3.1」。
            if !counters.Has(numId)
                counters[numId] := [0, 0, 0, 0, 0, 0, 0, 0, 0]
            arr := counters[numId]
            arr[ilvl + 1] += 1
            i := ilvl + 2
            while (i <= 9) {
                arr[i] := 0
                i++
            }

            ; ─── 生成编号文字 ───
            body := this._Format(lvl.text, arr, lvl.fmt, warnings)
            if (body = "")
                continue
            prefix := body . this._Suffix(lvl.suff)

            ; ─── 段落级取消编号 ───
            ; 光删样式上的 numPr 还不够：numbering.xml 的 `<w:lvl><w:pStyle w:val="a"/>`
            ; 仍然把「样式 a」关联到那套编号，pandoc 照样把标题当列表项。
            ; 加一个 `<w:numPr><w:numId w:val="0"/></w:numPr>`（0 在 numbering 里不存在）
            ; 是最明确的「这一段没有编号」—— Word 的「取消编号」按钮做的就是这件事。
            para := this._ClearNumbering(para)

            ; ─── 写进第一个 w:t ───
            ; 插到已有 run 的文字前面，而不是新建 run —— 这样编号继承该 run 的
            ; 字符格式（字号 / 加粗），不会在标题里冒出一段「默认字体」的序号。
            if !RegExMatch(para, '<w:t(\s[^>]*)?>', &tm) {
                skipped++
                continue
            }
            openTag := tm[0]
            ; `第 1 章 ` 这类编号末尾带空格，`w:t` 没有 xml:space="preserve" 会被裁掉。
            if !InStr(openTag, "xml:space")
                openTag := '<w:t xml:space="preserve">'
            openEnd := tm.Pos(0) + StrLen(tm[0])

            newPara := SubStr(para, 1, tm.Pos(0) - 1) . openTag
                . this._XmlText(prefix) . SubStr(para, openEnd)

            out .= SubStr(docXml, last, p - last) . newPara
            last := p + paraLen
            numbered++
        }

        if (numbered = 0 && skipped = 0)
            return {ok: true, xml: docXml, numbered: 0, skipped: 0, warnings: warnings}

        return {ok: true, xml: out . SubStr(docXml, last)
            , numbered: numbered, skipped: skipped, warnings: warnings}
    }

    ; ═══ 段落级「取消编号」═══
    ;
    ; 把这一段标成「没有编号」：优先改已有 numPr 的 numId 为 0，没有就插一个。
    ; `numId=0` 在 numbering.xml 里不存在 → pandoc 与 Word 都理解为「无编号」。
    ;
    ; ⚠ 为什么不直接删掉 numPr：删掉之后这一段会**继承样式**的编号（样式上的
    ;   numPr 虽然也被删了，但 numbering.xml 的 `<w:lvl><w:pStyle>` 仍在），
    ;   实测两种做法差别很大 —— 只删 numPr 时整篇仍被当有序列表。
    static _ClearNumbering(para) {
        ; ① 段落已有 numPr：把 numId 换成 0（ilvl 留着，pandoc 不看它）
        if RegExMatch(para, "(?s)<w:numPr>.*?</w:numPr>", &pm) {
            inner := pm[0]
            if RegExMatch(inner, '<w:numId\s+w:val="\d+"\s*/>', &nm)
                return StrReplace(para, inner
                    , StrReplace(inner, nm[0], '<w:numId w:val="0"/>'))
            return para
        }

        ; ② 有 pPr 没有 numPr：插在 pPr 末尾
        if RegExMatch(para, "(?s)<w:pPr>.*?</w:pPr>", &p2) {
            newPPr := SubStr(p2[0], 1, -StrLen("</w:pPr>"))
                . '<w:numPr><w:numId w:val="0"/></w:numPr></w:pPr>'
            return StrReplace(para, p2[0], newPPr)
        }

        ; ③ 连 pPr 都没有：紧跟 <w:p ...> 建一个
        if RegExMatch(para, '<w:p\b[^>]*>', &p3) {
            return SubStr(para, 1, StrLen(p3[0]))
                . '<w:pPr><w:numPr><w:numId w:val="0"/></w:numPr></w:pPr>'
                . SubStr(para, StrLen(p3[0]) + 1)
        }
        return para
    }

    ; ═══ 去掉标题样式上的编号（配合 FixDocument 使用）═══
    ;
    ; ⚠ **这一步不能省，否则前一步白做。** pandoc 的 docx reader 判断「这是不是列表项」
    ;   看的是段落的 numPr（段落直接设置，或从样式继承）。标题段落一旦仍挂着 numId，
    ;   pandoc 就把它当成 OrderedList，样式里的 heading 被忽略 —— 实测固化编号但不删
    ;   numPr 的结果是：整篇变成「1. NLP导论 / 1. 定义」这样的有序列表，一个标题都没有。
    ;   删掉之后：文字里已有编号，段落不再被当列表，heading N 正常输出成 `#`。
    ;
    ; 只删**标题样式**上的 numPr。普通项目符号 / 编号列表的样式必须原样留着，
    ; 那是真的列表，交给 pandoc 转 `-` / `1.`。
    ; 返回 {xml, stripped}
    static StripStyleNumbering(stylesXml) {
        out := ""
        last := 1
        stripped := 0
        pos := 1
        while (p := RegExMatch(stylesXml
            , '(?s)<w:style\b[^>]*w:type="paragraph"[^>]*>.*?</w:style>'
            , &m, pos)) {
            block := m[0]
            pos := p + StrLen(block)

            name := ""
            if RegExMatch(block, '<w:name\s+w:val="([^"]*)"', &nm)
                name := nm[1]
            outline := -1
            if RegExMatch(block, '<w:outlineLvl\s+w:val="(\d+)"', &om)
                outline := Integer(om[1])
            ; 判据与 _ParseStyles 一致：有 outlineLvl，或名字认得出是几级标题
            if !(outline >= 0 || (name != "" && DocxHeadingFix.LevelOf(name) > 0))
                continue

            if !RegExMatch(block, "(?s)<w:numPr>.*?</w:numPr>", &pm)
                continue

            newBlock := StrReplace(block, pm[0], "")
            out .= SubStr(stylesXml, last, p - last) . newBlock
            last := p + StrLen(block)
            stripped++
        }
        if (stripped = 0)
            return {xml: stylesXml, stripped: 0}
        return {xml: out . SubStr(stylesXml, last), stripped: stripped}
    }

    ; ═══ styles.xml → styleId → {title, numId, ilvl} ═══
    ;
    ; 判断「是不是标题」用两条：有 `w:outlineLvl`（Word 的大纲级别），
    ; 或者样式名能被 DocxHeadingFix.LevelOf 认出来（「二级标题」「半括号标题（五级）」等）。
    ; ⚠ 两条都要看：样本里「半括号标题（五级）」**没有** outlineLvl，
    ;   但它是实打实的五级标题；只看 outlineLvl 会漏掉它和它的编号。
    static _ParseStyles(stylesXml) {
        result := Map()
        pos := 1
        while (p := RegExMatch(stylesXml
            , '(?s)<w:style\b[^>]*w:type="paragraph"[^>]*>.*?</w:style>'
            , &m, pos)) {
            block := m[0]
            pos := p + StrLen(block)

            if !RegExMatch(block, 'w:styleId="([^"]+)"', &im)
                continue
            id := im[1]

            name := ""
            if RegExMatch(block, '<w:name\s+w:val="([^"]*)"', &nm)
                name := nm[1]

            outline := -1
            if RegExMatch(block, '<w:outlineLvl\s+w:val="(\d+)"', &om)
                outline := Integer(om[1])

            numId := ""
            ilvl := 0
            if RegExMatch(block, "(?s)<w:numPr>.*?</w:numPr>", &pm) {
                if RegExMatch(pm[0], '<w:numId\s+w:val="(\d+)"', &n2)
                    numId := Integer(n2[1])
                if RegExMatch(pm[0], '<w:ilvl\s+w:val="(\d+)"', &i2)
                    ilvl := Integer(i2[1])
            }

            title := (outline >= 0) || (name != "" && DocxHeadingFix.LevelOf(name) > 0)

            result[id] := {title: title, numId: numId, ilvl: ilvl}
        }
        return result
    }

    ; ═══ numbering.xml → numId → {levels: Map(ilvl → {text, fmt, suff})} ═══
    ;
    ; ⚠ `w:lvlOverride`（单个列表实例改起始值 / 屏蔽某一级）暂不处理：
    ;   实测样本里没有（查 `//w:num[w:lvlOverride]` 为空）。真遇到时编号会按
    ;   模板默认走，偏差会在转换汇总里体现为数字对不上 —— 那时再补。
    static _ParseNumbering(numXml) {
        ; abstractNumId → {levels}
        absMap := Map()
        pos := 1
        while (p := RegExMatch(numXml
            , '(?s)<w:abstractNum\b[^>]*w:abstractNumId="(\d+)"[^>]*>.*?</w:abstractNum>'
            , &m, pos)) {
            block := m[0]
            absId := Integer(m[1])
            pos := p + StrLen(block)

            levels := Map()
            lpos := 1
            while (lp := RegExMatch(block
                , '(?s)<w:lvl\b[^>]*w:ilvl="(\d+)"[^>]*>.*?</w:lvl>'
                , &lm, lpos)) {
                lvlBlock := lm[0]
                lvlIdx := Integer(lm[1])
                lpos := lp + StrLen(lvlBlock)

                text := ""
                if RegExMatch(lvlBlock, '<w:lvlText\s+w:val="([^"]*)"', &tm)
                    text := tm[1]
                fmt := "decimal"
                if RegExMatch(lvlBlock, '<w:numFmt\s+w:val="([^"]*)"', &fm)
                    fmt := fm[1]
                suff := "tab"
                if RegExMatch(lvlBlock, '<w:suff\s+w:val="([^"]*)"', &sm)
                    suff := sm[1]

                ; bullet 级别不参与编号固化（那是列表，交给 pandoc）
                if (fmt = "bullet" || text = "")
                    continue
                levels[lvlIdx] := {text: text, fmt: fmt, suff: suff}
            }
            absMap[absId] := {levels: levels}
        }

        ; numId → abstractNumId → 实际定义
        result := Map()
        pos := 1
        while (p := RegExMatch(numXml
            , '(?s)<w:num\b[^>]*w:numId="(\d+)"[^>]*>.*?</w:num>'
            , &m, pos)) {
            block := m[0]
            numId := Integer(m[1])
            pos := p + StrLen(block)
            if !RegExMatch(block, '<w:abstractNumId\s+w:val="(\d+)"', &am)
                continue
            absId := Integer(am[1])
            if absMap.Has(absId)
                result[numId] := absMap[absId]
        }
        return result
    }

    ; ═══ 模板 → 编号文字 ═══
    ;
    ; lvlText 里 `%1`..`%9` 是各级计数器（`%1` = 一级），`%%` 是字面百分号。
    ; 逐字符扫描而不是 RegExReplace：模板里混着 `%1.%2` 与 `（%6）` 这类
    ; 中文标点，用正则替换很容易把 `%%` 和 `%1` 的先后顺序搞错。
    static _Format(lvlText, counters, numFmt, warnings) {
        out := ""
        i := 1
        n := StrLen(lvlText)
        while (i <= n) {
            ch := SubStr(lvlText, i, 1)
            if (ch != "%") {
                out .= ch
                i++
                continue
            }
            next := SubStr(lvlText, i + 1, 1)
            if (next = "%") {
                out .= "%"
                i += 2
                continue
            }
            if RegExMatch(next, "^[1-9]$") {
                k := Integer(next)
                out .= this._Num(counters[k], numFmt, warnings)
                i += 2
                continue
            }
            out .= ch
            i++
        }
        return out
    }

    ; 单个数 → 显示形式。只做「确定能对」的几种；其余退回十进制并留一条警告。
    static _Num(v, numFmt, warnings) {
        if (numFmt = "" || numFmt = "decimal")
            return String(v)
        if (numFmt = "chineseCounting" || numFmt = "chineseCountingThousand"
            || numFmt = "chineseLegalSimplified")
            return this._Chinese(v)
        if (numFmt = "upperLetter" || numFmt = "lowerLetter") {
            ; 1..26 → A..Z；超出范围退回十进制
            if (v >= 1 && v <= 26) {
                ch := Chr(Ord("A") + v - 1)
                return (numFmt = "lowerLetter") ? StrLower(ch) : ch
            }
            return String(v)
        }
        ; 罗马数字 / 全角数字 / 序数词等：不猜，按十进制写，并明确告诉调用方
        warn := "编号格式未完全还原：" . numFmt
        if !this._HasWarning(warnings, warn)
            warnings.Push(warn)
        return String(v)
    }

    static _HasWarning(warnings, msg) {
        for w in warnings {
            if (w = msg)
                return true
        }
        return false
    }

    ; 1..99 的中文小写数字（chineseCounting）。标题级别用不到三位数。
    static _Chinese(v) {
        if (v <= 0 || v > 99)
            return String(v)
        if (v < 10)
            return this.CnDigits[v + 1]
        tens := v // 10
        ones := Mod(v, 10)
        head := (tens = 1) ? "十" : this.CnDigits[tens + 1] . "十"
        return (ones = 0) ? head : head . this.CnDigits[ones + 1]
    }

    ; 编号与标题文字之间的分隔：space / tab 都给一个空格，nothing 不给。
    static _Suffix(suff) {
        if (suff = "nothing")
            return ""
        return " "
    }

    ; 写进 XML 前要转义 `&` `<` `>` —— 模板里一般不会有，但自定义模板可能带 `&`，
    ; 未转义会让整份 document.xml 变成非法 XML，pandoc 直接读不出来。
    static _XmlText(s) {
        s := StrReplace(s, "&", "&amp;")
        s := StrReplace(s, "<", "&lt;")
        s := StrReplace(s, ">", "&gt;")
        return s
    }
}

