; ─── JsText：AHK 字符串 ↔ JS 字面量 ───
; 这一组盯的是「静默什么都不发生」那类故障：字面量写错一个字符，
; ExecuteScriptAsync 不报错，正文却悄悄变了样。
JsText_Tests() {
    Q := Chr(34)
    BS := Chr(92)

    T_Group("JsText.Escape")
    T_Same(JsText.Escape("abc"), Q . "abc" . Q, "普通字符串加外层引号")
    T_Same(JsText.Escape("中文"), Q . "中文" . Q, "中文原样透传")
    T_Same(JsText.Escape("a" . Q . "b"), Q . "a" . BS . Q . "b" . Q, "双引号转义")
    T_Same(JsText.Escape("a" . BS . "b"), Q . "a" . BS . BS . "b" . Q, "反斜杠转义")
    T_Same(JsText.Escape("a" . Chr(10) . "b"), Q . "a" . BS . "n" . "b" . Q, "换行写成 \n")
    T_Same(JsText.Escape("a" . Chr(9) . "b"), Q . "a" . BS . "t" . "b" . Q, "制表符写成 \t")
    ; NUL 是这条链路上最阴的字符：StrReplace 会把它当终止符，所以只能逐字符重建
    T_Same(JsText.Escape("a" . Chr(0) . "b"), Q . "a" . BS . "u0000" . "b" . Q, "NUL 写成 \u0000")
    ; U+2028 / 2029 在 ES 里是行终止符，出现在字面量里会语法错
    T_Same(JsText.Escape(Chr(0x2028)), Q . BS . "u2028" . Q, "U+2028 转义")
    T_Same(JsText.Escape(Chr(0x2029)), Q . BS . "u2029" . Q, "U+2029 转义")

    T_Group("JsText.Unquote")
    T_Same(JsText.Unquote(Q . "abc" . Q), "abc", "去掉外层引号")
    T_Same(JsText.Unquote(Q . "a" . BS . "n" . "b" . Q), "a" . Chr(10) . "b", "\n 还原成换行")
    T_Same(JsText.Unquote(Q . "a" . BS . Q . "b" . Q), "a" . Q . "b", "转义引号还原")
    T_Same(JsText.Unquote("null"), "null", "非字符串原样返回")
    T_Same(JsText.Unquote(""), "", "空串原样返回")

    T_Group("JsText 往返")
    ; 正文里随便一个引号 / 换行 / 反斜杠 / 制表符都可能打破字面量
    s := "第一行" . Chr(10) . "含 " . Q . "引号" . Q . " 与 " . BS . "反斜杠" . BS . " 还有 " . Chr(9) . "制表"
    T_Same(JsText.Unquote(JsText.Escape(s)), s, "转义后再解回必须一字不差")

    s2 := "emoji 😀 与中文混排"
    T_Same(JsText.Unquote(JsText.Escape(s2)), s2, "emoji 不被拆坏")
}
