#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════════
;  CommandLine —— 命令行里的可执行文件名（平台能力层）
; ═══════════════════════════════════════════════════════════════════════════
; 只做一件事：从一条命令行里取出**第一段**（可执行文件）的文件名，
; 供 WinGetList("ahk_exe <名字>") 认窗。
;
;   notepad.exe                                  → notepad.exe
;   "C:\Program Files\App\app.exe" --x           → app.exe
;   C:\Tools\app.exe -x                          → app.exe
;
; 纯字符串处理：不读 Config / State、不启动进程、不查窗口。
;
; ⚠ 不支持 `cmd /c start ...` 这类「启动器套启动器」—— 取到的会是 cmd，
;   按它认窗会认错。这类命令请在槽位里直接写目标 exe（含 .exe 扩展名）。
; ⚠ 只认双引号；单引号在 Windows 命令行里不是转义引号。

class CommandLine {
    static ExeOf(cmd) {
        s := Trim("" . cmd)
        if (s = "")
            return ""

        if (SubStr(s, 1, 1) = '"') {
            ; 从第 2 位找配对引号；没有配对视为非法
            end := InStr(s, '"',, 2)
            if !end
                return ""
            path := SubStr(s, 2, end - 2)
        } else {
            ; 第一个空格 / 制表符之前
            pos := 0
            loop StrLen(s) {
                ch := SubStr(s, A_Index, 1)
                if (ch = " " || ch = "`t") {
                    pos := A_Index
                    break
                }
            }
            path := (pos > 1) ? SubStr(s, 1, pos - 1) : s
        }

        path := Trim(path)
        if (path = "")
            return ""

        SplitPath(path, &name)
        return name
    }
}
