#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════════
;  TestLib —— 极简断言（不引框架）
; ═══════════════════════════════════════════════════════════════════════════
; 只做四件事：记组名、比数字、比字符串、比布尔。复杂断言容易把测试写成
; 第二套实现 —— 这里宁可少。
;
; 输出去向分两路：
;   ① 详细结果 → 日志文件（UTF-8），给人看、带中文；
;   ② stderr 只写一行 ASCII 摘要，给 tools\run-tests.ps1 判退出码。
; 分开的原因：stderr 里的中文在 PowerShell 侧容易被按 ANSI 解成乱码。

global T_Pass := 0
global T_Fail := 0
global T_GroupName := ""
global T_LogPath := ""

T_Init(logPath) {
    global T_LogPath, T_Pass, T_Fail
    T_LogPath := logPath
    T_Pass := 0
    T_Fail := 0
    ; 守卫在先：路径不存在时裸 FileDelete 会抛，后续整段都不执行
    if FileExist(logPath)
        FileDelete(logPath)
}

T_Line(s) {
    global T_LogPath
    FileAppend(s . "`n", T_LogPath, "UTF-8")
}

T_Group(name) {
    global T_GroupName
    T_GroupName := name
    T_Line("")
    T_Line("[ " . name . " ]")
}

; 数字相等。两边都必须真是数字 —— 否则「空串 = 0」会把错误判成通过。
T_Eq(actual, expected, what) {
    global T_Pass, T_Fail
    if (IsNumber(actual) && IsNumber(expected) && actual = expected) {
        T_Pass++
        T_Line("  ok    " . what)
        return true
    }
    T_Fail++
    T_Line("  FAIL  " . what)
    T_Line("        expected=" . String(expected) . "  actual=" . String(actual))
    return false
}

; 字符串完全一致（区分大小写、不 trim）
T_Same(actual, expected, what) {
    global T_Pass, T_Fail
    if (Type(actual) = "String" && Type(expected) = "String" && actual == expected) {
        T_Pass++
        T_Line("  ok    " . what)
        return true
    }
    T_Fail++
    T_Line("  FAIL  " . what)
    T_Line("        expected=[" . String(expected) . "]  actual=[" . String(actual) . "]")
    return false
}

; 布尔断言。要求严格 true / false —— FileExist 返回 "A" 这种必须判失败。
T_Ok(cond, what) {
    global T_Pass, T_Fail
    if (cond == true) {
        T_Pass++
        T_Line("  ok    " . what)
        return true
    }
    T_Fail++
    T_Line("  FAIL  " . what . "   (actual=" . String(cond) . ")")
    return false
}
