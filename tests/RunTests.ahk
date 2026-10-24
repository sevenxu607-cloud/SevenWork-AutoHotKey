#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════════
;  RunTests —— 纯逻辑回归（不建窗口、不读配置、不碰真实笔记）
; ═══════════════════════════════════════════════════════════════════════════
; 跑法（判退出码必须走包装器）：
;   powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-tests.ps1
;
; ⚠ 只 include 纯计算 / 纯字符串处理。**不要**把 Config / State / WebWindow 拉进来 ——
;   一旦测试需要真建窗口或读写生产配置，就不再是「一条命令跑完」的底座。
;   需要窗口的行为仍靠真机流程（按 Alt+Z / Alt+S 手验）。

#Include ..\src\WorkBench\Capabilities\Placement\RectMath.ahk
#Include ..\src\WorkBench\Capabilities\Placement\ZoneMath.ahk
#Include ..\src\WorkBench\Capabilities\Web\JsText.ahk
#Include ..\src\WorkBench\Capabilities\Document\DocxHeadingFix.ahk
#Include ..\src\WorkBench\Capabilities\Document\DocxNumberFix.ahk

#Include TestLib.ahk
#Include Cases\RectMath.Tests.ahk
#Include Cases\ZoneMath.Tests.ahk
#Include Cases\JsText.Tests.ahk
#Include Cases\Docx.Tests.ahk

; ─── 日志：与调试产物同目录，跑完看这一个文件 ───
logDir := A_Temp . "\SevenWorkDev"
if !FileExist(logDir)
    DirCreate(logDir)
logPath := logDir . "\tests.log"
T_Init(logPath)

; ─── 跑 ───
; 顶层 try：任何用例里的未捕获异常都要落到日志里，而不是让进程默默退出
try {
    RectMath_Tests()
    ZoneMath_Tests()
    JsText_Tests()
    Docx_Tests()
} catch as e {
    T_Line("")
    T_Line("!! 未捕获异常：" . e.Message)
    T_Line("   " . e.File . ":" . e.Line)
    T_Fail++
}

; ─── 汇总 ───
T_Line("")
T_Line("=== RESULT: " . T_Pass . " passed, " . T_Fail . " failed ===")
T_Line("log: " . logPath)

; stderr 只留 ASCII 摘要：包装器按退出码判定
FileAppend("RESULT pass=" . T_Pass . " fail=" . T_Fail . "`n", "**")
ExitApp(T_Fail ? 1 : 0)
