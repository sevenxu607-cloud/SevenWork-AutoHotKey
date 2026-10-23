; ─── DOCX 预处理：样式名识别与编号清理 ───
; 这两条直接决定 Alt+M 转出来的 Markdown 有没有标题、有没有编号，
; 而失败时 pandoc 往往仍然退出码 0 —— 所以只能靠这里的断言兜住。
Docx_Tests() {
    T_Group("DocxHeadingFix.LevelOf")
    T_Eq(DocxHeadingFix.LevelOf("二级标题"), 2, "「二级标题」→ 2")
    T_Eq(DocxHeadingFix.LevelOf("六级标题"), 6, "「六级标题」→ 6")
    T_Eq(DocxHeadingFix.LevelOf("圆括号标题（六级标题）"), 6, "先命中「六级标题」")
    T_Eq(DocxHeadingFix.LevelOf("半括号标题（五级）"), 5, "没有「级标题」时靠「（五级」兜住")
    T_Eq(DocxHeadingFix.LevelOf("标题 3"), 3, "「标题 3」→ 3")
    T_Eq(DocxHeadingFix.LevelOf("标题3"), 3, "「标题3」→ 3")
    T_Eq(DocxHeadingFix.LevelOf("heading 2"), 0, "已是标准名，不改")
    T_Eq(DocxHeadingFix.LevelOf("Heading 2"), 0, "大小写不敏感")
    T_Eq(DocxHeadingFix.LevelOf("正文"), 0, "非标题样式 → 0")

    T_Group("DocxHeadingFix.FixStyles")
    styles := '<w:styles>'
        . '<w:style w:type="paragraph" w:styleId="a0"><w:name w:val="二级标题"/><w:pPr/></w:style>'
        . '<w:style w:type="character" w:styleId="c1"><w:name w:val="三级标题"/></w:style>'
        . '</w:styles>'
    f := DocxHeadingFix.FixStyles(styles)
    T_Eq(f.count, 1, "只改段落样式，字符样式不动")
    T_Ok(InStr(f.xml, 'w:val="heading 2"') > 0, "段落样式名改成 heading 2")
    T_Ok(InStr(f.xml, 'w:val="三级标题"') > 0, "字符样式保持原名")

    empty := '<w:styles></w:styles>'
    f2 := DocxHeadingFix.FixStyles(empty)
    T_Eq(f2.count, 0, "无可改时 count = 0")
    T_Same(f2.xml, empty, "无可改时 xml 原样返回")

    T_Group("DocxNumberFix.FixDocument")
    r := DocxNumberFix.FixDocument("", "", "")
    T_Ok(!r.ok, "空入参应当失败")
    T_Same(r.reason, "bad-arg", "空入参原因为 bad-arg")

    ; numbering 里没有规则 → 原样返回，numbered = 0（不能把文档改坏）
    doc := '<w:document><w:body><w:p><w:pPr><w:pStyle w:val="a0"/></w:pPr>'
        . '<w:r><w:t>定义</w:t></w:r></w:p></w:body></w:document>'
    st := '<w:styles><w:style w:type="paragraph" w:styleId="a0"><w:name w:val="二级标题"/></w:style></w:styles>'
    r2 := DocxNumberFix.FixDocument(doc, st, '<w:numbering></w:numbering>')
    T_Ok(r2.ok, "无编号规则时仍成功")
    T_Eq(r2.numbered, 0, "无编号规则时 numbered = 0")
    T_Same(r2.xml, doc, "无编号规则时文档原样返回")

    T_Group("DocxNumberFix.StripStyleNumbering")
    ; 标题样式上的 numPr 必须删（否则 pandoc 把它当有序列表，整篇没有标题）；
    ; 列表样式的 numPr 必须留（那是真的列表，要转成 - / 1.）
    sStyles := '<w:styles>'
        . '<w:style w:type="paragraph" w:styleId="a0"><w:name w:val="二级标题"/>'
        . '<w:pPr><w:numPr><w:ilvl w:val="1"/><w:numId w:val="3"/></w:numPr></w:pPr></w:style>'
        . '<w:style w:type="paragraph" w:styleId="list"><w:name w:val="List Bullet"/>'
        . '<w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="9"/></w:numPr></w:pPr></w:style>'
        . '</w:styles>'
    sp := DocxNumberFix.StripStyleNumbering(sStyles)
    T_Eq(sp.stripped, 1, "只清标题样式上的 numPr")
    T_Ok(InStr(sp.xml, 'w:numId w:val="9"') > 0, "列表样式的 numPr 必须保留")
    T_Ok(InStr(sp.xml, 'w:numId w:val="3"') = 0, "标题样式的 numPr 已删除")

    ; 没有标题样式编号 → 原样返回
    sp2 := DocxNumberFix.StripStyleNumbering('<w:styles></w:styles>')
    T_Eq(sp2.stripped, 0, "无可清时 stripped = 0")
    T_Same(sp2.xml, '<w:styles></w:styles>', "无可清时 xml 原样返回")
}
