#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════════
;  CommandLine 纯逻辑用例
; ═══════════════════════════════════════════════════════════════════════════
;  只测字符串解析：不启动进程、不查窗口。
;  覆盖裸 exe、带引号路径、参数、空串、未闭合引号、目录结尾。

CommandLine_Tests() {
    T_Group("CommandLine.ExeOf 基本")

    T_Same(CommandLine.ExeOf("notepad.exe"), "notepad.exe"
        , "裸 exe 原样返回")
    T_Same(CommandLine.ExeOf("C:\Tools\app.exe -x"), "app.exe"
        , "无引号路径 + 参数")
    T_Same(CommandLine.ExeOf('"C:\Program Files\App\app.exe" --arg'), "app.exe"
        , "带空格路径（双引号）+ 参数")
    T_Same(CommandLine.ExeOf('  "D:\a b\c.exe"  '), "c.exe"
        , "前导 / 尾随空白不影响")
    T_Same(CommandLine.ExeOf("MyApp.EXE"), "MyApp.EXE"
        , "大小写原样保留")
    T_Same(CommandLine.ExeOf("D:\app.exe"), "app.exe"
        , "盘根路径")

    T_Group("CommandLine.ExeOf 非法与边界")
    T_Same(CommandLine.ExeOf(""), "", "空串返回空串")
    T_Same(CommandLine.ExeOf("   "), "", "纯空白返回空串")
    T_Same(CommandLine.ExeOf('""'), "", "空引号返回空串")
    T_Same(CommandLine.ExeOf('"unterminated'), "", "未闭合引号返回空串")
    T_Same(CommandLine.ExeOf("C:\Tools\"), "", "目录结尾取不到文件名")

    T_Group("CommandLine.ExeOf 不支持的形式")
    T_Same(CommandLine.ExeOf("cmd /c start notepad.exe"), "cmd"
        , "启动器套启动器只会取到 cmd（文档已写明不支持）")
}
